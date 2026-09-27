/* Vercel Serverless Function: POST /api/gdrive-token
   Google ドライブへの接続を「一度つなげば続く」ようにするためのサーバー側の処理。

   ・exchange：ブラウザ（Google の小さな画面）で受け取った認可コードを、アクセストークンと
     リフレッシュトークンに交換する。リフレッシュトークンは Supabase の
     oshikatsu_gdrive_tokens に本人の行として保存し、アクセストークンだけをブラウザへ返す。
   ・refresh：保存したリフレッシュトークンで、新しいアクセストークン（1時間有効）を発行して返す。
     PC・スマホなど、同じアカウントでログインしたどの端末からでも使える。
   ・revoke：Google 側の許可を取り消し、保存したリフレッシュトークンを消す。

   呼び出しには、ログイン中の Supabase のアクセストークン（Authorization: Bearer ...）が必要。
   Supabase への読み書きもその本人のトークンで行うため、行レベルセキュリティ（RLS）で本人の行しか扱えない。
   OAuth クライアントシークレット（GOOGLE_OAUTH_CLIENT_SECRET）はこの中だけで使い、ブラウザへは返さない。 */

var TABLE = "oshikatsu_gdrive_tokens";

function pick(env, names){
  for(var i=0;i<names.length;i++){
    var v = env[names[i]];
    if(typeof v === "string" && v.trim()) return v.trim();
  }
  return "";
}

function send(res, status, obj){
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.end(JSON.stringify(obj));
}

async function readBody(req){
  if(req.body && typeof req.body === "object") return req.body;
  if(typeof req.body === "string"){ try{ return JSON.parse(req.body); }catch(e){ return {}; } }
  var chunks = [];
  for await (var c of req) chunks.push(c);
  try{ return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}"); }catch(e){ return {}; }
}

async function googleToken(params){
  var r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(params).toString()
  });
  var j = {};
  try{ j = await r.json(); }catch(e){}
  return { ok: r.ok, status: r.status, body: j };
}

module.exports = async function handler(req, res){
  if(req.method !== "POST") return send(res, 405, { error: "method_not_allowed" });

  var env = process.env;
  var sbUrl = pick(env, ["NEXT_PUBLIC_SUPABASE_URL", "SUPABASE_URL"]).replace(/\/+$/, "");
  var sbKey = pick(env, ["NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", "NEXT_PUBLIC_SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ANON_KEY"]);
  var clientId = pick(env, ["GOOGLE_OAUTH_CLIENT_ID", "GOOGLE_CLIENT_ID", "NEXT_PUBLIC_GOOGLE_CLIENT_ID"]);
  var clientSecret = pick(env, ["GOOGLE_OAUTH_CLIENT_SECRET", "GOOGLE_CLIENT_SECRET"]);
  if(!sbUrl || !sbKey || !clientId || !clientSecret) return send(res, 501, { error: "not_configured" });

  var auth = String(req.headers["authorization"] || "");
  var jwt = auth.indexOf("Bearer ") === 0 ? auth.slice(7).trim() : "";
  if(!jwt) return send(res, 401, { error: "login_required" });

  // ログイン中の本人かを Supabase に確かめる
  var ur = await fetch(sbUrl + "/auth/v1/user", { headers: { apikey: sbKey, Authorization: "Bearer " + jwt } });
  if(!ur.ok) return send(res, 401, { error: "login_required" });
  var user = await ur.json();
  if(!user || !user.id) return send(res, 401, { error: "login_required" });

  var rest = sbUrl + "/rest/v1/" + TABLE;
  var sbHeaders = { apikey: sbKey, Authorization: "Bearer " + jwt, "Content-Type": "application/json" };
  async function loadRefresh(){
    var r = await fetch(rest + "?select=refresh_token&user_id=eq." + encodeURIComponent(user.id), { headers: sbHeaders });
    if(!r.ok) throw new Error("db read " + r.status);
    var rows = await r.json();
    return rows && rows[0] ? rows[0].refresh_token : "";
  }
  async function saveRefresh(token){
    var r = await fetch(rest + "?on_conflict=user_id", {
      method: "POST",
      headers: Object.assign({ Prefer: "resolution=merge-duplicates,return=minimal" }, sbHeaders),
      body: JSON.stringify({ user_id: user.id, refresh_token: token, updated_at: new Date().toISOString() })
    });
    if(!r.ok) throw new Error("db write " + r.status);
  }
  async function deleteRefresh(){
    await fetch(rest + "?user_id=eq." + encodeURIComponent(user.id), { method: "DELETE", headers: sbHeaders });
  }

  var body = await readBody(req);
  var action = body.action;

  try{
    if(action === "exchange"){
      if(!body.code) return send(res, 400, { error: "code_required" });
      var ex = await googleToken({
        code: String(body.code), client_id: clientId, client_secret: clientSecret,
        redirect_uri: "postmessage", grant_type: "authorization_code"
      });
      if(!ex.ok || !ex.body.access_token) return send(res, 400, { error: ex.body.error || "exchange_failed" });
      // 保存できなくても（表がまだ無いなど）、この端末では1時間使えるようにアクセストークンは返す
      var stored = false;
      try{
        if(ex.body.refresh_token){ await saveRefresh(ex.body.refresh_token); stored = true; }
        else { stored = !!(await loadRefresh()); }
      }catch(e){ console.error("gdrive-token save", e); }
      return send(res, 200, { access_token: ex.body.access_token, expires_in: ex.body.expires_in || 3600, linked: stored });
    }

    if(action === "refresh"){
      var rt = await loadRefresh();
      if(!rt) return send(res, 404, { error: "not_linked" });
      var rf = await googleToken({ refresh_token: rt, client_id: clientId, client_secret: clientSecret, grant_type: "refresh_token" });
      if(!rf.ok || !rf.body.access_token){
        // 許可が取り消された・期限切れのときは、保存したトークンを消して「再接続が必要」にする
        if(rf.body.error === "invalid_grant"){ await deleteRefresh(); return send(res, 404, { error: "not_linked" }); }
        return send(res, 502, { error: rf.body.error || "refresh_failed" });
      }
      if(rf.body.refresh_token && rf.body.refresh_token !== rt) await saveRefresh(rf.body.refresh_token);
      return send(res, 200, { access_token: rf.body.access_token, expires_in: rf.body.expires_in || 3600, linked: true });
    }

    if(action === "revoke"){
      var old = await loadRefresh();
      if(old){
        try{ await fetch("https://oauth2.googleapis.com/revoke?token=" + encodeURIComponent(old), { method: "POST" }); }catch(e){}
      }
      await deleteRefresh();
      return send(res, 200, { ok: true });
    }

    return send(res, 400, { error: "unknown_action" });
  }catch(e){
    console.error("gdrive-token", e);
    return send(res, 500, { error: "server_error" });
  }
};

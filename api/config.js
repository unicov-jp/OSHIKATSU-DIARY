/* Vercel Serverless Function: GET /api/config
   Returns the public Supabase connection info (project URL + anon/publishable
   key) and the browser Google Maps API key from the project's environment
   variables, so index.html can stay a
   build-free static file. Only browser-safe values are ever returned: a key
   that turns out to be a service_role / secret key is refused. */

function pick(env, names){
  for(var i=0;i<names.length;i++){
    var v = env[names[i]];
    if(typeof v === "string" && v.trim()) return v.trim();
  }
  return "";
}

/* true for keys that must never reach a browser */
function isSecretKey(key){
  if(key.indexOf("sb_secret_") === 0) return true;
  var parts = key.split(".");
  if(parts.length !== 3) return false;
  try{
    var payload = JSON.parse(Buffer.from(parts[1].replace(/-/g,"+").replace(/_/g,"/"), "base64").toString("utf8"));
    return payload && payload.role === "service_role";
  }catch(e){
    return false;
  }
}

module.exports = function handler(req, res){
  var env = process.env;
  var url = pick(env, ["NEXT_PUBLIC_SUPABASE_URL", "SUPABASE_URL"]);
  var key = pick(env, [
    "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
    "NEXT_PUBLIC_SUPABASE_ANON_KEY",
    "SUPABASE_PUBLISHABLE_KEY",
    "SUPABASE_ANON_KEY"
  ]);
  if(key && isSecretKey(key)) key = "";
  // Google Maps のブラウザ用キー（HTTPリファラーで制限して使う前提）
  var mapsKey = pick(env, ["GOOGLE_MAPS_API_KEY", "NEXT_PUBLIC_GOOGLE_MAPS_API_KEY"]);

  res.statusCode = 200;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.end(JSON.stringify({ supabaseUrl: url, supabaseAnonKey: key, googleMapsApiKey: mapsKey }));
};

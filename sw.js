/* 推し活手帳 Service Worker
   ・アプリとしてインストールできるようにする（PWA）
   ・画面（HTML）は常にネットワーク優先で取り、つながらないときだけ保存済みのものを出す
   ・アイコンや同梱ライブラリなどの静的ファイルはキャッシュから返し、裏で更新する
   ・/api/ と外部サービス（Supabase・Google など）への通信は一切キャッシュしない */
var CACHE = "oshikatsu-v1";
var PRECACHE = [
  "/",
  "/index.html",
  "/privacy.html",
  "/manifest.webmanifest",
  "/vendor/supabase-js-2.117.2.js",
  "/icons/icon-192.png",
  "/icons/icon-512.png",
  "/icons/apple-touch-icon.png",
  "/icons/favicon-32.png"
];

self.addEventListener("install", function(event){
  event.waitUntil(
    caches.open(CACHE).then(function(cache){ return cache.addAll(PRECACHE); }).then(function(){ return self.skipWaiting(); })
  );
});

self.addEventListener("activate", function(event){
  event.waitUntil(
    caches.keys().then(function(keys){
      return Promise.all(keys.filter(function(k){ return k!==CACHE; }).map(function(k){ return caches.delete(k); }));
    }).then(function(){ return self.clients.claim(); })
  );
});

self.addEventListener("fetch", function(event){
  var req = event.request;
  if(req.method!=="GET") return;
  var url = new URL(req.url);
  if(url.origin!==self.location.origin) return;       // 外部サービスは素通し
  if(url.pathname.indexOf("/api/")===0) return;       // 設定APIは常に最新を取る

  // 画面（ページ遷移）はネットワーク優先
  if(req.mode==="navigate" || (req.headers.get("accept")||"").indexOf("text/html")>=0){
    event.respondWith(
      fetch(req).then(function(res){
        var copy = res.clone();
        caches.open(CACHE).then(function(cache){ cache.put(url.pathname==="/" ? "/" : req, copy); });
        return res;
      }).catch(function(){
        return caches.match(req).then(function(hit){ return hit || caches.match("/"); });
      })
    );
    return;
  }

  // 静的ファイルはキャッシュ優先（裏で最新に更新）
  event.respondWith(
    caches.match(req).then(function(hit){
      var network = fetch(req).then(function(res){
        if(res && res.ok){
          var copy = res.clone();
          caches.open(CACHE).then(function(cache){ cache.put(req, copy); });
        }
        return res;
      }).catch(function(){ return hit; });
      return hit || network;
    })
  );
});

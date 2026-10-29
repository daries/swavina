#pragma once
#include <pgmspace.h>

// Halaman konfigurasi WiFi (GET /). Memakai endpoint JSON yang sama dengan
// aplikasi: /status, /scan, /wifi, /reset.
static const char WEB_PAGE[] PROGMEM = R"HTML(<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Swavina WiFi</title>
<style>
:root{--accent:#C35423;--bg:#F8F8F8;--card:#fff;--text:#111;--muted:#666;--border:#ddd;--ok:#28A745;--err:#DC3545;--warn:#E08A00}
@media (prefers-color-scheme:dark){:root{--bg:#000;--card:#1C1C1E;--text:#fff;--muted:#aaa;--border:#333}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.5 -apple-system,system-ui,Segoe UI,Roboto,sans-serif}
main{max-width:480px;margin:0 auto;padding:16px}
h1{font-size:24px;margin:8px 0 2px;color:var(--accent)}
.sub{color:var(--muted);font-size:14px;margin-bottom:16px}
.card{background:var(--card);border-radius:18px;padding:16px;margin-bottom:14px;box-shadow:0 2px 10px #0000001a}
h2{font-size:17px;margin:0 0 10px}
.row{display:flex;justify-content:space-between;gap:12px;padding:4px 0;font-size:15px}
.row span:first-child{color:var(--muted)}
.row span:last-child{font-weight:600;text-align:right;word-break:break-all}
.ok{color:var(--ok)}.err{color:var(--err)}.warn{color:var(--warn)}
label{display:block;font-size:14px;color:var(--muted);margin:10px 0 4px}
input{width:100%;padding:12px;border:1px solid var(--border);border-radius:12px;background:transparent;color:var(--text);font-size:16px}
input:focus{outline:none;border-color:var(--accent)}
.pw{position:relative}.pw button{position:absolute;right:6px;top:6px;width:auto;padding:6px 10px;background:none;color:var(--muted);font-size:13px}
button{width:100%;padding:13px;border:0;border-radius:12px;background:var(--accent);color:#fff;font-size:16px;font-weight:700;cursor:pointer}
button:disabled{opacity:.5}
button.ghost{background:none;color:var(--accent);padding:6px;width:auto;font-size:14px}
button.danger{background:none;color:var(--err);border:1px solid var(--err);margin-top:4px}
.head{display:flex;justify-content:space-between;align-items:center}
ul{list-style:none;margin:0;padding:0;max-height:240px;overflow:auto}
li{display:flex;justify-content:space-between;padding:10px 8px;border-radius:10px;cursor:pointer;font-size:15px}
li:hover,li.sel{background:#C3542322}
li small{color:var(--muted)}
#msg{margin-top:12px;font-size:14px;min-height:1em}
</style>
</head>
<body>
<main>
<h1 id="name">Swavina</h1>
<div class="sub">Pengaturan WiFi perangkat</div>

<div class="card">
<h2>Status</h2>
<div class="row"><span>Mode</span><span id="mode">-</span></div>
<div class="row"><span>WiFi</span><span id="wifi">-</span></div>
<div class="row"><span>Jaringan</span><span id="ssid">-</span></div>
<div class="row"><span>IP</span><span id="ip">-</span></div>
<div class="row"><span>Terapi</span><span id="therapy">-</span></div>
</div>

<div class="card">
<div class="head"><h2>Jaringan Terdeteksi</h2><button class="ghost" id="scanBtn" onclick="scan()">Scan</button></div>
<ul id="nets"><li><small>Memindai...</small></li></ul>
</div>

<div class="card">
<h2>Ubah WiFi</h2>
<form onsubmit="save(event)">
<label for="s">Nama WiFi (SSID)</label>
<input id="s" autocomplete="off" autocapitalize="none" required>
<label for="p">Password</label>
<div class="pw"><input id="p" type="password" autocomplete="off"><button type="button" onclick="togglePw()">Lihat</button></div>
<div style="height:14px"></div>
<button id="saveBtn">Simpan &amp; Hubungkan</button>
</form>
<div id="msg"></div>
</div>

<div class="card">
<h2>Reset</h2>
<div class="sub" style="margin:0 0 10px">Hapus WiFi tersimpan. Perangkat restart ke mode Access Point.</div>
<button class="danger" onclick="resetWifi()">Hapus WiFi Tersimpan</button>
</div>
</main>
<script>
const $=id=>document.getElementById(id);
const WIFI={idle:['Belum diatur','warn'],connecting:['Menghubungkan...','warn'],connected:['Terhubung','ok'],failed:['Gagal terhubung','err']};
let polling=null;
function stop(){clearInterval(polling);polling=null;}

async function j(url,opt){const r=await fetch(url,opt);return r.json();}

async function info(){try{const i=await j('/info');$('name').textContent=i.name;document.title=i.name+' WiFi';}catch(e){}}

async function status(){
  try{
    const s=await j('/status');
    const w=WIFI[s.wifi]||[s.wifi,''];
    $('wifi').textContent=w[0];$('wifi').className=w[1];
    $('mode').textContent=s.ap?'Access Point + WiFi':'WiFi';
    $('ssid').textContent=s.ssid||'-';
    $('ip').textContent=s.ip||'-';
    $('therapy').textContent=s.therapy==='running'?'Berjalan ('+Math.ceil((s.remaining||0)/60)+' menit lagi)':'Tidak berjalan';
    return s;
  }catch(e){return null;}
}

function bars(r){return r>=-60?'▂▄▆█':r>=-75?'▂▄▆':'▂▄';}

async function scan(){
  $('scanBtn').disabled=true;$('nets').innerHTML='<li><small>Memindai...</small></li>';
  try{
    const d=await j('/scan');const seen={};const list=$('nets');list.innerHTML='';
    d.networks.sort((a,b)=>b.rssi-a.rssi).forEach(n=>{
      if(!n.ssid||seen[n.ssid])return;seen[n.ssid]=1;
      const li=document.createElement('li');
      const a=document.createElement('span');a.textContent=n.ssid;
      const b=document.createElement('small');b.textContent=(n.secure?'🔒 ':'')+bars(n.rssi);
      li.append(a,b);
      li.onclick=()=>{$('s').value=n.ssid;document.querySelectorAll('li').forEach(x=>x.classList.remove('sel'));li.classList.add('sel');$('p').focus();};
      list.append(li);
    });
    if(!list.children.length)list.innerHTML='<li><small>Tidak ada jaringan. Ketik SSID manual.</small></li>';
  }catch(e){$('nets').innerHTML='<li><small>Gagal memindai.</small></li>';}
  $('scanBtn').disabled=false;
}

function togglePw(){const p=$('p');p.type=p.type==='password'?'text':'password';}

function msg(t,c){$('msg').textContent=t;$('msg').className=c||'';}

async function save(e){
  e.preventDefault();
  const ssid=$('s').value.trim();if(!ssid)return;
  $('saveBtn').disabled=true;
  try{
    const r=await j('/wifi',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({ssid,password:$('p').value})});
    if(!r.ok)throw new Error(r.error||'gagal');
  }catch(err){msg('Gagal mengirim data WiFi.','err');$('saveBtn').disabled=false;return;}
  msg('Menghubungkan ke "'+ssid+'"...','warn');
  const end=Date.now()+40000;let lost=0;
  stop();
  polling=setInterval(async()=>{
    const s=await status();
    if(!s){if(++lost>=4){stop();msg('Koneksi ke perangkat terputus. Sambungkan HP ke "'+ssid+'" lalu buka http://swavina.local','warn');$('saveBtn').disabled=false;}return;}
    lost=0;
    if(s.wifi==='connected'&&s.ssid===ssid){stop();msg('Berhasil! IP perangkat: '+s.ip+'. Sambungkan HP ke "'+ssid+'" lalu buka http://swavina.local atau http://'+s.ip,'ok');$('saveBtn').disabled=false;}
    else if(s.wifi==='failed'){stop();msg('Gagal masuk ke "'+ssid+'". Periksa nama WiFi dan password.'+(s.ssid?' Perangkat kembali ke "'+s.ssid+'".':''),'err');$('saveBtn').disabled=false;}
    else if(Date.now()>end){stop();msg('Waktu habis. Coba lagi.','err');$('saveBtn').disabled=false;}
  },1500);
}

async function resetWifi(){
  if(!confirm('Hapus WiFi tersimpan dan restart perangkat?'))return;
  try{await fetch('/reset',{method:'POST'});}catch(e){}
  msg('Perangkat restart. Sambungkan HP ke WiFi "'+$('name').textContent+'" (password swavina123) lalu buka http://192.168.4.1','warn');
}

info();status();scan();setInterval(()=>{if(!polling)status();},5000);
</script>
</body>
</html>
)HTML";

let htmlTemplate = #"""
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  :root{
    --bg:#ececec; --panel:#ffffff; --ink:#1d1d1f; --muted:#86868b; --line:#dcdcdc;
    --accent:#0a72ff; --code-bg:#f2f2f4; --hover:#f0f0f2; --hair:rgba(0,0,0,.08); --danger:#e0384e;
  }
  @media (prefers-color-scheme: dark){
    :root{ --bg:#232326; --panel:#2b2b2f; --ink:#f2f2f5; --muted:#98989f; --line:#3a3a40;
           --accent:#4c93ff; --code-bg:#1c1c20; --hover:#34343a; --hair:rgba(255,255,255,.08); --danger:#ff5f6d; }
  }
  *{box-sizing:border-box}
  html,body{margin:0;height:100%;
    font:13px/1.5 -apple-system,BlinkMacSystemFont,'SF Pro Text',system-ui,sans-serif;
    background:var(--bg);color:var(--ink);-webkit-font-smoothing:antialiased}
  .wrap{display:flex;flex-direction:column;height:100vh}

  /* nav bar */
  header{display:flex;align-items:center;gap:8px;height:44px;padding:0 10px;-webkit-app-region:drag}
  header .mid{flex:1;text-align:center;font-size:13px;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  header .nav{-webkit-app-region:no-drag;appearance:none;border:0;background:transparent;color:var(--accent);
    font-size:13px;font-weight:500;cursor:pointer;padding:6px 8px;border-radius:7px;min-width:58px;white-space:nowrap}
  header .nav:hover{background:var(--hover)}
  header .nav.r{text-align:right} header .nav.l{text-align:left}
  header .nav.mut{color:var(--muted)} header .nav.strong{font-weight:600}
  header .plus{-webkit-app-region:no-drag;appearance:none;border:0;background:transparent;color:var(--accent);
    font-size:20px;font-weight:300;cursor:pointer;line-height:1;padding:2px 8px;border-radius:7px}
  header .plus:hover{background:var(--hover)}
  .spring{flex:1}

  main{flex:1;overflow:auto;background:var(--panel);margin:0 12px;border:.5px solid var(--line);border-radius:12px}
  main.pad{padding:16px 18px 20px}
  main::-webkit-scrollbar{width:9px}
  main::-webkit-scrollbar-thumb{background:rgba(140,140,150,.4);border-radius:9px;border:2px solid transparent;background-clip:content-box}

  /* home list */
  .list{padding:4px 0}
  .row{display:flex;align-items:center;gap:10px;padding:11px 16px;cursor:pointer;border-bottom:.5px solid var(--line)}
  .row:last-child{border-bottom:0}
  .row:hover{background:var(--hover)}
  .row .ic{width:30px;height:30px;border-radius:7px;background:var(--code-bg);display:flex;align-items:center;justify-content:center;font-size:15px;flex:0 0 auto}
  .row .tx{flex:1;min-width:0}
  .row .tt{font-weight:600;font-size:13.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .row .pv{color:var(--muted);font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:1px}
  .row .chev{color:var(--muted);font-size:16px;flex:0 0 auto}
  .row .cat{font-size:10px;font-weight:600;color:var(--muted);background:var(--code-bg);border:.5px solid var(--line);
    padding:2px 8px;border-radius:999px;flex:0 0 auto;white-space:nowrap}
  .row .tags{display:flex;flex-wrap:wrap;gap:4px;margin-top:4px}
  .row .tag{font-size:10px;color:var(--accent);background:var(--code-bg);padding:1px 6px;border-radius:5px;white-space:nowrap;border:.5px solid transparent}
  .cdot{display:inline-block;width:7px;height:7px;border-radius:50%;margin-right:5px;vertical-align:middle}
  .chips.ntop{position:sticky;top:0;background:var(--panel);z-index:2;border-bottom:.5px solid var(--line);
    padding:8px 12px;flex-wrap:wrap;overflow-x:visible;row-gap:6px}
  .chip .cc{opacity:.65;font-weight:700;font-size:10px;margin-left:2px}
  .chip.active .cc{opacity:.85}
  .empty{color:var(--muted);text-align:center;padding:40px 20px;font-size:13px}

  /* rendered markdown */
  h1.md{font-size:17px;font-weight:600;margin:0 0 10px}
  h2.md{font-size:13.5px;font-weight:600;margin:18px 0 6px}
  h2.md::before{content:"";display:block;height:.5px;background:var(--line);margin-bottom:9px}
  h3.md{font-size:12.5px;font-weight:600;margin:13px 0 4px;color:var(--muted)}
  p{margin:6px 0} ul{margin:6px 0;padding-left:18px} li{margin:3px 0}
  hr{border:0;border-top:.5px solid var(--line);margin:14px 0}
  code{background:var(--code-bg);padding:1px 5px;border-radius:5px;font:11.5px/1.4 ui-monospace,SFMono-Regular,Menlo,monospace}
  pre{background:var(--code-bg);border:.5px solid var(--line);border-radius:8px;padding:10px 12px;overflow-x:auto;margin:8px 0}
  pre code{background:none;padding:0;font-size:11.5px;color:var(--ink)}
  blockquote{margin:9px 0;padding:2px 0 2px 12px;border-left:2px solid var(--line);color:var(--muted)}
  a{color:var(--accent);text-decoration:none} strong{font-weight:600}

  /* editor */
  .edit{display:flex;flex-direction:column;height:100%}
  .edit textarea{flex:1;width:100%;resize:none;border:0;outline:0;background:transparent;color:var(--ink);
    padding:16px 18px;font:12.5px/1.6 ui-monospace,SFMono-Regular,Menlo,monospace;-webkit-app-region:no-drag}
  .hint{color:var(--muted);font-size:11px;padding:6px 18px;border-top:.5px solid var(--line);display:flex;align-items:center}
  .hint .del{margin-left:auto;color:var(--danger);cursor:pointer;font-weight:500}
  .nminput{margin:14px 18px 2px;padding:9px 12px;border:.5px solid var(--line);border-radius:9px;
    background:var(--code-bg);color:var(--ink);font-size:14px;font-weight:600;outline:none;-webkit-app-region:no-drag}
  .nminput:focus{border-color:var(--accent)}
  /* markdown formatting toolbar */
  .mdbar{display:flex;align-items:center;gap:1px;padding:7px 12px;border-bottom:.5px solid var(--line);
    overflow-x:auto;-webkit-app-region:no-drag}
  .mdbar::-webkit-scrollbar{display:none}
  .mdbar button{flex:0 0 auto;appearance:none;border:0;background:transparent;color:var(--ink);
    min-width:30px;height:28px;border-radius:7px;font-size:13px;cursor:pointer;padding:0 8px;line-height:1}
  .mdbar button:hover{background:var(--hover)}
  .mdbar button b{font-weight:800} .mdbar button i{font-style:italic;font-family:Georgia,serif}
  .mdbar .sep{width:1px;height:18px;background:var(--line);margin:0 5px;flex:0 0 auto}

  /* clipboard */
  .chips{display:flex;gap:6px;padding:8px 12px 6px;overflow-x:auto}
  .chips::-webkit-scrollbar{display:none}
  .chip{flex:0 0 auto;border:.5px solid var(--line);background:var(--code-bg);color:var(--muted);
    padding:4px 11px;border-radius:999px;font-size:11.5px;font-weight:600;cursor:pointer;white-space:nowrap}
  .chip.active{background:var(--accent);border-color:var(--accent);color:#fff}
  .daterow{font-size:10.5px;font-weight:700;color:var(--muted);text-transform:uppercase;letter-spacing:.5px;padding:13px 16px 5px}
  .clip{display:flex;gap:10px;align-items:flex-start;padding:10px 14px;border-bottom:.5px solid var(--line);cursor:pointer}
  .clip:last-child{border-bottom:0}
  .clip:hover{background:var(--hover)}
  .clip .cbody{flex:1;min-width:0}
  .badge{display:inline-block;font-size:9px;font-weight:700;letter-spacing:.4px;padding:2px 6px;border-radius:5px;
    background:var(--code-bg);color:var(--muted);text-transform:uppercase;margin-bottom:5px}
  .badge.link{color:#0a72ff} .badge.code{color:#a855f7} .badge.path{color:#0ea5a5}
  .badge.image{color:#e0873a} .badge.video{color:#e0384e} .badge.file{color:#7d8797} .badge.text{color:#7d8797}
  .badge.email{color:#0a72ff} .badge.phone{color:#22a06b} .badge.color{color:#e0873a} .badge.ip{color:#7c7cff} .badge.error{color:#e0384e}
  .badge.pdf{color:#d4380d}
  .cnt{display:inline-block;margin-left:6px;font-size:9.5px;font-weight:700;padding:2px 6px;border-radius:999px;
    background:var(--accent);color:#fff;vertical-align:top}
  .swatch{width:42px;height:42px;border-radius:9px;border:.5px solid var(--line);flex:0 0 auto}
  .search{margin:2px 12px 4px;padding:7px 11px;border:.5px solid var(--line);border-radius:9px;
    background:var(--code-bg);color:var(--ink);font-size:12.5px;outline:none}
  .search:focus{border-color:var(--accent)}
  .clip .star{color:var(--muted);font-size:14px;padding:0 3px;line-height:1.3;align-self:flex-start;cursor:pointer}
  .clip .star.on{color:#f0a500}
  .prev{font-size:12.5px;color:var(--ink);white-space:pre-wrap;word-break:break-word;
    display:-webkit-box;-webkit-line-clamp:4;-webkit-box-orient:vertical;overflow:hidden}
  .prev.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;background:var(--code-bg);
    padding:8px 10px;border-radius:7px;-webkit-line-clamp:6;line-height:1.45}
  .prev.linkish{color:var(--accent)}
  .clip img.thumb{max-width:130px;max-height:84px;border-radius:7px;border:.5px solid var(--line);display:block}
  .cmeta{font-size:10.5px;color:var(--muted);margin-top:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .clip .x{color:var(--muted);font-size:15px;align-self:flex-start;padding:0 4px;line-height:1.2}
  .clip .x:hover{color:var(--danger)}
  .ficon{width:42px;height:42px;border-radius:9px;background:var(--code-bg);display:flex;align-items:center;justify-content:center;font-size:20px;flex:0 0 auto}

  /* embedded attachments in notes */
  .imgblock{margin:10px 0;text-align:center}
  .imgblock img{max-width:100%;max-height:340px;border-radius:9px;border:.5px solid var(--line);cursor:zoom-in}
  img.embinl{max-height:200px;max-width:100%;border-radius:7px;border:.5px solid var(--line);vertical-align:middle;cursor:zoom-in}
  .pdfblock{margin:10px 0;border:.5px solid var(--line);border-radius:10px;overflow:hidden;background:var(--code-bg)}
  .pdfhead{display:flex;align-items:center;gap:7px;padding:8px 11px;font-size:12.5px;font-weight:600}
  .pdfhead .pact{appearance:none;border:0;background:transparent;color:var(--accent);font-size:11.5px;
    font-weight:600;cursor:pointer;padding:3px 7px;border-radius:6px}
  .pdfhead .pact:hover{background:var(--hover)}
  .pdfblock embed{width:100%;height:420px;border:0;border-top:.5px solid var(--line);background:#555}
  a.al{cursor:pointer}
  a.wl{cursor:pointer;background:var(--code-bg);padding:1px 6px;border-radius:6px;font-weight:600;
    border:.5px solid var(--line)}
  a.wl.miss{color:var(--muted);border-style:dashed}
  .backlinks{margin-top:18px;padding-top:10px;border-top:.5px solid var(--line)}
  .backlinks .bt{font-size:10.5px;font-weight:700;color:var(--muted);text-transform:uppercase;letter-spacing:.5px;margin-bottom:5px}
  .backlinks a{display:inline-block;margin:2px 6px 2px 0;cursor:pointer}

  /* list metadata */
  .row .when{font-size:10.5px;color:var(--muted);flex:0 0 auto;white-space:nowrap}
  .row .pin{font-size:11px;flex:0 0 auto}

  /* clip action chips (path / file / open / reveal) */
  .cacts{display:flex;gap:4px;margin-top:6px}
  .cacts button{appearance:none;border:.5px solid var(--line);background:var(--panel);color:var(--accent);
    font-size:10px;font-weight:600;cursor:pointer;padding:2px 8px;border-radius:999px}
  .cacts button:hover{background:var(--hover)}

  /* full-height layout while printing to PDF */
  html.pdfmode, .pdfmode body{height:auto}
  .pdfmode .wrap{height:auto}
  .pdfmode main{overflow:visible;height:auto;margin:0;border:0;border-radius:0}
  .pdfmode header,.pdfmode footer,.pdfmode #toast{display:none}
  .pdfmode .pdfblock embed{display:none}

  /* copy toast */
  #toast{position:fixed;left:50%;bottom:16px;transform:translate(-50%,20px);opacity:0;pointer-events:none;
    display:flex;align-items:center;gap:10px;max-width:82%;padding:9px 13px;border-radius:12px;
    background:var(--panel);border:.5px solid var(--line);box-shadow:0 8px 26px rgba(0,0,0,.28);
    transition:opacity .18s ease,transform .18s ease;z-index:50}
  #toast.show{opacity:1;transform:translate(-50%,0)}
  #toast .ticon{width:26px;height:26px;border-radius:6px;background:var(--code-bg);display:flex;align-items:center;
    justify-content:center;font-size:14px;flex:0 0 auto;overflow:hidden}
  #toast .ticon img.thumb{max-width:26px;max-height:26px;border:0;border-radius:5px}
  #toast .ticon .swatch,#toast .ticon .ficon{width:26px;height:26px;border-radius:6px;font-size:14px}
  #toast .tt{font-size:11px;font-weight:700;color:var(--accent);text-transform:uppercase;letter-spacing:.3px}
  #toast .ts{font-size:12px;color:var(--ink);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:340px}

  footer{display:flex;align-items:center;gap:2px;padding:7px 10px 9px}
  .btn{appearance:none;border:0;background:transparent;color:var(--accent);
    padding:6px 9px;border-radius:7px;font-size:12.5px;font-weight:500;cursor:pointer}
  .btn:hover{background:var(--hover)} .btn.mut{color:var(--muted)}
</style></head>
<body><div class="wrap">
  <header id="bar"></header>
  <main id="app"></main>
  <footer id="foot"></footer>
  <div id="toast"></div>
</div>
<script>
  const NOTES = /*__NOTES__*/;
  let CLIPS = /*__CLIPS__*/;
  let view = "/*__VIEW__*/";           // home | note | edit | clips | new
  let active = /*__ACTIVE__*/;
  const injectedDraft = /*__DRAFT__*/null;   // an interrupted edit, restored by the app
  let draft = null;
  if(view==='new'){ draft={name:'',body:'',isNew:true}; view='edit'; }
  else if(injectedDraft && injectedDraft.body!==undefined && view!=='clips'){
    draft={name:injectedDraft.name||'', body:injectedDraft.body||'', isNew:!!injectedDraft.isNew};
    const i=NOTES.findIndex(n=>n.name===draft.name);
    if(!draft.isNew && i>=0) active=i;
    view='edit';
  }
  let noteFilter = 'All';
  let noteSearch = '';
  let clipFilter = 'all';
  let clipSearch = '';

  function cur(){ return NOTES[active] || {name:'',title:'',body:''}; }
  function send(action, extra){ try{ window.webkit.messageHandlers.bridge.postMessage(Object.assign({action:action}, extra||{})); }catch(e){} }
  function escHtml(s){ return (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
  function titleOf(body){ const m=stripFM(body).split('\n').find(l=>/^#\s/.test(l.trim())); return m?m.trim().replace(/^#\s+/,''):'Untitled'; }
  // Remove a leading YAML frontmatter block (--- … ---) so it never shows in the note view or preview.
  function stripFM(body){
    const s=body||'';
    if(!/^---\s*\n/.test(s)) return s;
    const m=s.match(/^---\s*\n[\s\S]*?\n---\s*\n?/);
    return m ? s.slice(m[0].length) : s;
  }
  function firstText(body){
    const lines=stripFM(body).split('\n');
    for(let i=0;i<lines.length;i++){ let l=lines[i].trim();
      if(!l||/^#/.test(l)||l.indexOf('---')===0||l.indexOf('```')===0) continue;
      return l.replace(/[*`>#_\[\]]/g,'').replace(/\(([^)]+)\)/g,'').slice(0,90);
    } return 'No additional text';
  }
  function slugify(t){ return (t||'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'') || 'note'; }
  function uniqueSlug(t){ let b=slugify(t), s=b, i=2; const names=NOTES.map(n=>n.name.toLowerCase());
    while(names.indexOf(s)>=0){ s=b+'-'+i; i++; } return s; }

  // ---------- attachments + wiki links ----------
  function assetUrl(n){ return 'cherry://asset/'+encodeURIComponent(n); }
  function isImgName(n){ return /\.(png|jpe?g|gif|heic|webp|tiff?|bmp|svg)$/i.test(n); }
  function noteIndexByRef(ref){
    const w=(ref||'').trim().toLowerCase();
    return NOTES.findIndex(n=>n.title.toLowerCase()===w||n.name.toLowerCase()===w);
  }
  function openWiki(ref){
    const i=noteIndexByRef(ref);
    if(i>=0){ openNote(i); return; }
    if(confirm('No note called “'+ref+'” yet. Create it?')){
      draft={name:'', body:'# '+ref+'\n\n', isNew:true, presetName:ref}; view='edit'; route();
      setTimeout(function(){ const nm=document.getElementById('nm'); if(nm){ nm.value=ref; } },0);
    }
  }
  function wikiLink(m,ref){
    const i=noteIndexByRef(ref);
    return '<a class="wl'+(i<0?' miss':'')+'" data-n="'+ref+'" onclick="openWiki(this.dataset.n)">'+ref+'</a>';
  }
  function inl(s){ return s
    .replace(/`([^`]+)`/g,function(m,c){return '<code>'+c+'</code>';})
    .replace(/!\[([^\]]*)\]\(assets\/([^)]+)\)/g,function(m,alt,f){
      return '<img class="embinl" data-f="'+f+'" src="'+assetUrl(f)+'" onclick="send(\'open-asset\',{file:this.dataset.f})">'; })
    .replace(/!\[([^\]]*)\]\(([^)]+)\)/g,'<img class="embinl" src="$2">')
    .replace(/\*\*([^*]+)\*\*/g,'<strong>$1</strong>')
    .replace(/\[([^\]]+)\]\(assets\/([^)]+)\)/g,function(m,txt,f){
      return '<a class="al" data-f="'+f+'" onclick="send(\'open-asset\',{file:this.dataset.f})">📎 '+txt+'</a>'; })
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g,'<a href="$2">$1</a>')
    .replace(/\[\[([^\[\]|]+)\]\]/g,wikiLink); }
  // Block-level attachment cards: a lone image gets a figure, a lone PDF an inline viewer.
  function attachBlock(line){
    let m=line.match(/^!?\[([^\]]*)\]\(assets\/([^)]+)\)\s*$/); if(!m) return null;
    const f=m[2], label=m[1]||f, ef=escHtml(f);
    if(isImgName(f)){
      return '<div class="imgblock"><img data-f="'+ef+'" src="'+assetUrl(f)+'" onclick="send(\'open-asset\',{file:this.dataset.f})"></div>';
    }
    const isPdf=/\.pdf$/i.test(f);
    let h='<div class="pdfblock"><div class="pdfhead">'+(isPdf?'📕':'📎')+' '+escHtml(label)+'<span class="spring"></span>'
      +'<button class="pact" data-f="'+ef+'" onclick="send(\'open-asset\',{file:this.dataset.f})">Open</button>'
      +'<button class="pact" data-f="'+ef+'" onclick="send(\'reveal-asset\',{file:this.dataset.f})">Reveal</button>'
      +'<button class="pact" data-f="'+ef+'" onclick="send(\'copy-asset-path\',{file:this.dataset.f});showToast(\'📎\',\'Copied\',\'Full path on clipboard\')">Path</button></div>';
    if(isPdf) h+='<embed src="'+assetUrl(f)+'" type="application/pdf">';
    return h+'</div>';
  }
  function md(src){
    const L=(src||'').split('\n'); let out=''; let i=0; let inList=false;
    const closeL=()=>{ if(inList){out+='</ul>';inList=false;} };
    while(i<L.length){ let line=L[i];
      if(line.trim().indexOf('```')===0){ closeL(); i++; let code='';
        while(i<L.length && L[i].trim().indexOf('```')!==0){ code+=L[i]+'\n'; i++; } i++;
        out+='<pre><code>'+escHtml(code.replace(/\n$/,''))+'</code></pre>'; continue; }
      const ab=attachBlock(line.trim()); if(ab){ closeL(); out+=ab; i++; continue; }
      if(/^#{1,6}\s/.test(line)){ closeL(); const m=line.match(/^(#{1,6})\s+(.*)$/); let lvl=m[1].length; if(lvl>3)lvl=3;
        out+='<h'+lvl+' class="md">'+inl(escHtml(m[2]))+'</h'+lvl+'>'; }
      else if(/^\s*---\s*$/.test(line)){ closeL(); out+='<hr>'; }
      else if(/^>\s?/.test(line)){ closeL(); let bq='';
        while(i<L.length && /^>\s?/.test(L[i])){ bq+=inl(escHtml(L[i].replace(/^>\s?/,'')))+'<br>'; i++; }
        out+='<blockquote>'+bq.replace(/<br>$/,'')+'</blockquote>'; continue; }
      else if(/^\s*[-*]\s+/.test(line)){ if(!inList){out+='<ul>';inList=true;} out+='<li>'+inl(escHtml(line.replace(/^\s*[-*]\s+/,'')))+'</li>'; }
      else if(line.trim()===''){ closeL(); }
      else { closeL(); out+='<p>'+inl(escHtml(line))+'</p>'; }
      i++;
    } closeL(); return out;
  }

  const bar=()=>document.getElementById('bar');
  const appEl=()=>document.getElementById('app');
  const foot=()=>document.getElementById('foot');

  function goHome(){ view='home'; draft=null; route(); }
  function openNote(i){ active=i; view='note'; route(); }
  function openEdit(){ const n=cur(); draft={name:n.name, body:n.body, isNew:false}; view='edit'; route(); }
  function addNote(){ draft={name:'', body:'', isNew:true}; view='edit'; route(); }
  function cancelEdit(){ draft=null; send('draft-clear'); view = (NOTES.length? (cur().name?'note':'home'):'home'); route(); }
  function saveEdit(){
    let body=document.getElementById('ta').value;
    let name=draft.name;
    if(draft.isNew){
      const typed=((document.getElementById('nm')||{}).value||'').trim();
      let title = typed || titleOf(body);
      if(!title || title==='Untitled'){ alert('Give the note a name first.'); const nm=document.getElementById('nm'); if(nm) nm.focus(); return; }
      // ensure the note opens with its name as an H1 title
      if(!/^#{1,6}\s/.test(body.trim())){ body='# '+title+(body.trim()?'\n\n'+body:'\n\n'); }
      name=uniqueSlug(title);
      NOTES.push({name:name,title:titleOf(body),body:body}); active=NOTES.length-1;
    } else {
      const title=titleOf(body);
      const i=NOTES.findIndex(x=>x.name===name); if(i>=0){ NOTES[i].body=body; NOTES[i].title=title; active=i; }
    }
    send('save',{name:name, body:body});
    draft=null; view='note'; route();
    showToast('💾','Saved',name+'.md');
  }

  // ---------- draft safety net (nothing typed is ever lost) ----------
  function __snapDraft(){
    if(view!=='edit'||!draft) return null;
    const ta=document.getElementById('ta'); if(!ta) return null;
    const nm=document.getElementById('nm');
    return {name:(draft.isNew?((nm&&nm.value)||''):draft.name), body:ta.value, isNew:!!draft.isNew};
  }
  window.__snapDraft=__snapDraft;
  let draftT=null;
  function draftTick(){
    if(draftT) clearTimeout(draftT);
    draftT=setTimeout(function(){ const d=__snapDraft(); if(d) send('draft',d); },600);
  }

  // Insert text at the cursor (used by the app after importing an attachment).
  function __insertSnippet(text){
    const ta=document.getElementById('ta'); if(!ta) return;
    const s=ta.selectionStart||0;
    ta.setRangeText(text, s, ta.selectionEnd||s, 'end');
    ta.focus(); updateWC(); draftTick();
  }
  window.__insertSnippet=__insertSnippet;

  function updateWC(){
    const ta=document.getElementById('ta'), el=document.getElementById('wc');
    if(!ta||!el) return;
    const t=ta.value, words=(t.match(/\S+/g)||[]).length;
    el.textContent=words+' words · '+t.length+' chars';
  }

  // ---------- full-page PDF export helpers ----------
  function __preparePDF(){
    document.documentElement.classList.add('pdfmode');
    return document.documentElement.scrollHeight;
  }
  function __endPDF(){ document.documentElement.classList.remove('pdfmode'); }
  window.__preparePDF=__preparePDF; window.__endPDF=__endPDF;

  // ---------- pin / unpin (stored as frontmatter, so it survives in the .md file) ----------
  function setFM(body,key,val){
    let s=body||'';
    const m=s.match(/^---\s*\n([\s\S]*?)\n---\s*\n?/);
    if(m){
      let block=m[1].split('\n').filter(function(l){ return l.split(':')[0].trim().toLowerCase()!==key; });
      if(val!==null) block.push(key+': '+val);
      return '---\n'+block.join('\n')+'\n---\n'+s.slice(m[0].length);
    }
    return val===null ? s : '---\n'+key+': '+val+'\n---\n'+s;
  }
  function togglePin(){
    const n=cur(); if(!n.name) return;
    n.pinned=!n.pinned;
    n.body=setFM(n.body,'pinned',n.pinned?'true':null);
    send('save',{name:n.name, body:n.body});
    showToast(n.pinned?'📌':'📄', n.pinned?'Pinned':'Unpinned', n.title);
    route();
  }

  // ---------- markdown formatting toolbar (for people who don't write Markdown) ----------
  function taEl(){ return document.getElementById('ta'); }
  function surround(before, after){
    const ta=taEl(); if(!ta) return; const s=ta.selectionStart, e=ta.selectionEnd;
    const sel=ta.value.slice(s,e);
    ta.setRangeText(before+sel+after, s, e, 'end');
    if(sel){ ta.selectionStart=s+before.length; ta.selectionEnd=s+before.length+sel.length; }
    else { ta.selectionStart=ta.selectionEnd=s+before.length; }
    ta.focus();
  }
  function linePrefix(prefix){
    const ta=taEl(); if(!ta) return; const s=ta.selectionStart, e=ta.selectionEnd; const v=ta.value;
    const ls=v.lastIndexOf('\n',s-1)+1; let le=v.indexOf('\n',e); if(le<0) le=v.length;
    const block=v.slice(ls,le).split('\n').map(function(l){ return prefix+l; }).join('\n');
    ta.setRangeText(block, ls, le, 'end'); ta.focus();
  }
  function mdLink(){
    const ta=taEl(); if(!ta) return; const s=ta.selectionStart, e=ta.selectionEnd;
    const sel=ta.value.slice(s,e)||'text';
    ta.setRangeText('['+sel+'](url)', s, e, 'end');
    const us=s+sel.length+3; ta.selectionStart=us; ta.selectionEnd=us+3; ta.focus();   // select "url" placeholder
  }
  function mdToolbar(){
    return '<div class="mdbar">'
     +'<button title="Heading" onclick="linePrefix(\'## \')">H</button>'
     +'<button title="Bold (⌘B)" onclick="surround(\'**\',\'**\')"><b>B</b></button>'
     +'<button title="Italic (⌘I)" onclick="surround(\'*\',\'*\')"><i>I</i></button>'
     +'<span class="sep"></span>'
     +'<button title="Bulleted list" onclick="linePrefix(\'- \')">&#8226;</button>'
     +'<button title="Quote" onclick="linePrefix(\'> \')">&#10077;</button>'
     +'<button title="Inline code" onclick="surround(\'`\',\'`\')">&lt;/&gt;</button>'
     +'<span class="sep"></span>'
     +'<button title="Link" onclick="mdLink()">&#128279;</button>'
     +'<button title="Link to another note — [[Note]]" onclick="wikiInsert()">[[&nbsp;]]</button>'
     +'<button title="Attach image / PDF / file" onclick="send(\'attach\')">&#128206;</button>'
     +'</div>';
  }
  function wikiInsert(){
    const ta=taEl(); if(!ta) return; const s=ta.selectionStart, e=ta.selectionEnd;
    const sel=ta.value.slice(s,e);
    if(sel){ surround('[[',']]'); return; }
    const names=NOTES.map(function(n){return n.title;}).join(', ');
    const ref=prompt('Link to which note?'+(names?'\n('+names.slice(0,200)+(names.length>200?'…':'')+')':''),'');
    if(!ref) return;
    ta.setRangeText('[['+ref+']]', s, e, 'end'); ta.focus(); draftTick();
  }
  function delNote(){ const n=cur(); if(!confirm('Delete “'+n.title+'”? This removes the note and its Spotlight app.')) return;
    send('delete',{name:n.name}); NOTES.splice(active,1); active=0; draft=null; view='home'; route(); }

  // ---------- clipboard ----------
  function showClips(){ view='clips'; route(); }
  const KINDS=[['fav','★'],['all','All'],['link','Links'],['email','Emails'],['code','Code'],['error','Errors'],
    ['path','Paths'],['color','Colors'],['ip','IPs'],['phone','Phones'],['image','Images'],['video','Videos'],['pdf','PDFs'],['file','Files'],['text','Text']];
  function twoDigit(n){ return (n<10?'0':'')+n; }
  function agoStr(ts){
    const s=Math.max(0,Date.now()/1000-ts);
    if(s<60) return 'now'; if(s<3600) return Math.floor(s/60)+'m';
    if(s<86400) return Math.floor(s/3600)+'h'; if(s<86400*30) return Math.floor(s/86400)+'d';
    const d=new Date(ts*1000); return d.toLocaleDateString(undefined,{month:'short',day:'numeric'});
  }
  function timeStr(ts){ const d=new Date(ts*1000); return twoDigit(d.getHours())+':'+twoDigit(d.getMinutes()); }
  function dayKey(ts){ const d=new Date(ts*1000); const n=new Date();
    const dd=new Date(d.getFullYear(),d.getMonth(),d.getDate()); const t0=new Date(n.getFullYear(),n.getMonth(),n.getDate());
    const diff=Math.round((t0-dd)/86400000);
    if(diff===0) return 'Today'; if(diff===1) return 'Yesterday'; if(diff>1&&diff<7) return d.toLocaleDateString(undefined,{weekday:'long'});
    return d.toLocaleDateString(undefined,{year:'numeric',month:'short',day:'numeric'}); }
  function icon(kind){ return kind==='video'?'🎞':kind==='pdf'?'📕':kind==='file'?'📄':kind==='image'?'🖼':'📋'; }
  function hasFileActions(c){ return c.path && (c.kind==='image'||c.kind==='video'||c.kind==='file'||c.kind==='pdf'); }
  function clipActs(c){
    if(!hasFileActions(c)) return '';
    return '<div class="cacts">'
      +'<button onclick="actClip(event,\''+c.id+'\',\'clip-copy-path\',\'Path copied\')">Copy Path</button>'
      +'<button onclick="actClip(event,\''+c.id+'\',\'clip-copy-file\',\'File copied — paste it anywhere\')">Copy File</button>'
      +'<button onclick="actClip(event,\''+c.id+'\',\'clip-open\',\'Opening…\')">Open</button>'
      +'<button onclick="actClip(event,\''+c.id+'\',\'clip-reveal\',\'Showing in Finder\')">Reveal</button></div>';
  }
  function actClip(ev,id,action,msg){
    ev.stopPropagation();
    const c=CLIPS.find(x=>x.id===id); if(!c) return;
    send(action,{id:id});
    showToast(clipInner(c)||icon(c.kind), msg, shortLabel(c));
  }
  function badgeText(c){ return c.kind==='code' ? ('Code'+(c.lang?' · '+c.lang:'')) : c.kind; }
  function clipInner(c){
    if(c.kind==='image'){ return (c.thumb?'<img class="thumb" src="'+c.thumb+'">':'<div class="ficon">🖼</div>'); }
    if(c.kind==='video'||c.kind==='file'||c.kind==='pdf'){ return '<div class="ficon">'+icon(c.kind)+'</div>'; }
    if(c.kind==='color'){ return '<div class="swatch" style="background:'+escHtml(c.preview||'#000')+'"></div>'; }
    return '';
  }
  function clipMain(c){
    let cls='prev', txt=escHtml(c.preview||'');
    if(c.kind==='code'||c.kind==='path'||c.kind==='error') cls='prev mono';
    else if(c.kind==='link'||c.kind==='email') cls='prev linkish';
    let meta='';
    if(c.kind==='image'||c.kind==='video'||c.kind==='file'||c.kind==='pdf'){ txt=escHtml(c.name||'file'); meta=escHtml(c.path||''); }
    else if(c.len&&c.len>1400){ meta=(c.len)+' chars'; }
    const cnt=(c.count&&c.count>1)?'<span class="cnt">×'+c.count+'</span>':'';
    return '<span class="badge '+c.kind+'">'+escHtml(badgeText(c))+'</span>'+cnt
      +'<div class="'+cls+'">'+txt+'</div>'+(meta?'<div class="cmeta">'+meta+'</div>':'');
  }
  function shortLabel(c){
    if(c.kind==='image'||c.kind==='video'||c.kind==='file'||c.kind==='pdf') return c.name||'file';
    let s=(c.preview||'').replace(/\s+/g,' ').trim();
    return s.length>60 ? s.slice(0,60)+'…' : s;
  }
  function copyClip(id){
    const c=CLIPS.find(x=>x.id===id); if(!c) return;
    send('clip-copy',{id:id});
    showToast(clipInner(c), 'Now copied · '+badgeText(c), shortLabel(c));
  }
  let toastT=null;
  function showToast(iconHtml, title, sub){
    let t=document.getElementById('toast');
    t.innerHTML='<div class="ticon">'+(iconHtml||'📋')+'</div><div class="tbody"><div class="tt">'
      +escHtml(title)+'</div><div class="ts">'+escHtml(sub||'')+'</div></div>';
    t.classList.add('show');
    if(toastT) clearTimeout(toastT);
    toastT=setTimeout(function(){ t.classList.remove('show'); }, 1900);
  }
  function toggleFav(id,ev){ ev.stopPropagation(); const c=CLIPS.find(x=>x.id===id); if(!c) return;
    c.fav=!c.fav; send('clip-fav',{id:id,fav:!!c.fav}); renderClipList(); }
  function delClip(id,ev){ ev.stopPropagation(); send('clip-delete',{id:id}); CLIPS=CLIPS.filter(c=>c.id!==id); renderClipList(); }
  function clearClips(){ if(!confirm('Clear all clipboard history?')) return; send('clip-clear'); CLIPS=[]; route(); }
  function clipMatches(c){
    const q=clipSearch.trim().toLowerCase(); if(!q) return true;
    return ((c.preview||'')+' '+(c.name||'')+' '+(c.path||'')+' '+(c.lang||'')+' '+c.kind).toLowerCase().indexOf(q)>=0;
  }
  function renderClipList(){
    const cont=document.getElementById('cliplist'); if(!cont) return;
    const list=CLIPS.filter(c=>(clipFilter==='all'||(clipFilter==='fav'?c.fav:c.kind===clipFilter))&&clipMatches(c));
    if(!list.length){ cont.innerHTML='<div class="empty">'+(clipSearch?'No matches.':'Nothing here yet.<br>Copy something and it shows up.')+'</div>'; return; }
    let html='', lastDay='';
    list.forEach(function(c){
      const dk=dayKey(c.ts);
      if(dk!==lastDay){ html+='<div class="daterow">'+escHtml(dk)+'</div>'; lastDay=dk; }
      html+='<div class="clip" onclick="copyClip(\''+c.id+'\')">'
        +clipInner(c)+'<div class="cbody">'+clipMain(c)+clipActs(c)+'<div class="cmeta">'+timeStr(c.ts)+'</div></div>'
        +'<span class="star'+(c.fav?' on':'')+'" onclick="toggleFav(\''+c.id+'\',event)">'+(c.fav?'★':'☆')+'</span>'
        +'<span class="x" onclick="delClip(\''+c.id+'\',event)">×</span></div>';
    });
    cont.innerHTML=html;
  }

  // ---------- notes home list (category + text search) ----------
  // Stable per-category color: fixed hues for the known categories, hashed palette for new ones.
  const CAT_COLORS={'AI & LLM':'#a855f7','Social & Posting':'#0a72ff','Infra & Data':'#0ea5a5',
    'Servers & SSH':'#e0873a','Reference':'#7c7cff','General':'#7d8797'};
  const CAT_PALETTE=['#a855f7','#0a72ff','#0ea5a5','#e0873a','#e0384e','#22a06b','#7c7cff','#d4a017'];
  function catColor(c){
    if(!c) c='General';
    if(CAT_COLORS[c]) return CAT_COLORS[c];
    let h=0; for(let i=0;i<c.length;i++){ h=(h*31+c.charCodeAt(i))>>>0; }
    return CAT_PALETTE[h%CAT_PALETTE.length];
  }
  function noteMatches(n){
    const q=noteSearch.trim().toLowerCase(); if(!q) return true;
    const hay=((n.title||'')+' '+(n.category||'')+' '+((n.tags||[]).join(' '))+' '+stripFM(n.body||'')).toLowerCase();
    return hay.indexOf(q)>=0;
  }
  function renderNoteList(){
    const cont=document.getElementById('notelist'); if(!cont) return;
    const rows=NOTES.map(function(n,idx){ return {n:n,idx:idx}; })
      .filter(function(o){ return noteFilter==='All' || (o.n.category||'General')===noteFilter; })
      .filter(function(o){ return noteMatches(o.n); })
      .map(function(o){ const n=o.n; const col=catColor(n.category||'General');
        const tags=(n.tags&&n.tags.length)?'<div class="tags">'+n.tags.slice(0,4).map(function(t){return '<span class="tag" style="color:'+col+';border-color:'+col+'40">'+escHtml(t)+'</span>';}).join('')+'</div>':'';
        const pill='<div class="cat" style="color:'+col+';border-color:'+col+'66">'+escHtml(n.category||'General')+'</div>';
        return '<div class="row" onclick="openNote('+o.idx+')"><div class="ic" style="color:'+col+'">'+(n.pinned?'📌':(n.name==='email'?'✉️':'🗄️'))+'</div>'
          +'<div class="tx"><div class="tt">'+escHtml(n.title)+'</div><div class="pv">'+escHtml(firstText(n.body))+'</div>'+tags+'</div>'
          +((noteFilter==='All'&&!noteSearch)?pill:'')
          +(n.mtime?'<div class="when">'+agoStr(n.mtime)+'</div>':'')
          +'<div class="chev">›</div></div>';
      }).join('');
    cont.innerHTML = rows || '<div class="empty">'+(noteSearch?'No notes match “'+escHtml(noteSearch)+'”.':'Nothing in “'+escHtml(noteFilter)+'”.')+'</div>';
  }

  function route(){
    if(view==='home'){
      bar().innerHTML='<button class="nav l" title="Clipboard" onclick="showClips()">📋 Clipboard</button>'
        +'<div class="mid">🍒 Cherry</div><span class="spring"></span>'
        +'<button class="plus" title="New note" onclick="addNote()">+</button>';
      appEl().className='';
      if(!NOTES.length){ appEl().innerHTML='<div class="empty">No notes yet.<br>Tap + to add one.</div>'; }
      else {
        // category chips (built from the notes; "All" first, then categories in first-seen order)
        const cats=['All'];
        NOTES.forEach(function(n){ const c=(n.category||'General'); if(cats.indexOf(c)<0) cats.push(c); });
        if(cats.indexOf(noteFilter)<0) noteFilter='All';
        window.__cats=cats;
        const chips=cats.map(function(c,i){
          const cnt=(c==='All')?NOTES.length:NOTES.filter(function(n){return (n.category||'General')===c;}).length;
          const on=(noteFilter===c), isAll=(c==='All'), col=catColor(c);
          let style='', dot='';
          if(!isAll){ if(on){ style=' style="background:'+col+';border-color:'+col+';color:#fff"'; }
                      else { style=' style="border-color:'+col+'66"'; dot='<span class="cdot" style="background:'+col+'"></span>'; } }
          return '<div class="chip'+(on?' active':'')+'"'+style+' onclick="noteFilter=window.__cats['+i+'];noteSearch=\'\';route()">'
            +dot+escHtml(c)+' <span class="cc">'+cnt+'</span></div>'; }).join('');
        appEl().innerHTML='<div class="chips ntop">'+chips+'</div>'
          +'<input class="search" id="noteq" type="search" placeholder="Search notes — title, tag, text…" '
          +'oninput="noteSearch=this.value;renderNoteList()" value="'+escHtml(noteSearch)+'">'
          +'<div class="list" id="notelist"></div>';
        renderNoteList();
        const q=document.getElementById('noteq'); if(noteSearch&&q){ q.focus(); q.setSelectionRange(q.value.length,q.value.length); }
      }
      foot().innerHTML='<button class="btn mut" onclick="send(\'reveal\')">Folder</button>'
        +'<span class="spring"></span><button class="btn mut" onclick="send(\'quit\')">Quit</button>';
    }
    else if(view==='note'){
      const n=cur();
      bar().innerHTML='<button class="nav l" onclick="goHome()">‹ Notes</button>'
        +'<div class="mid">'+(n.pinned?'📌 ':'')+escHtml(n.title)+'</div>'
        +'<button class="nav r strong" onclick="openEdit()">Edit</button>';
      // backlinks — every other note whose body wiki-links [[here]]
      const refs=NOTES.map(function(o,idx){return {o:o,idx:idx};}).filter(function(x){
        if(x.o.name===n.name) return false;
        const b=(x.o.body||'').toLowerCase();
        return b.indexOf('[['+n.title.toLowerCase()+']]')>=0 || b.indexOf('[['+n.name.toLowerCase()+']]')>=0;
      });
      const bl=refs.length?'<div class="backlinks"><div class="bt">Linked from</div>'
        +refs.map(function(x){return '<a class="wl" onclick="openNote('+x.idx+')">'+escHtml(x.o.title)+'</a>';}).join('')+'</div>':'';
      appEl().className='pad'; appEl().innerHTML=md(stripFM(n.body))+bl; appEl().scrollTop=0;
      foot().innerHTML='<button class="btn" onclick="send(\'copy\',{text:stripFM(cur().body)});showToast(\'📋\',\'Copied\',cur().title)">Copy</button>'
        +'<button class="btn" onclick="togglePin()">'+(n.pinned?'Unpin':'Pin')+'</button>'
        +'<button class="btn" onclick="send(\'export-pdf\',{name:cur().title})">PDF</button>'
        +'<button class="btn" onclick="send(\'cherrytree\')">CherryTree</button>'
        +'<button class="btn mut" onclick="send(\'reveal\')">Folder</button>'
        +'<span class="spring"></span><button class="btn mut" onclick="send(\'quit\')">Quit</button>';
    }
    else if(view==='edit'){
      bar().innerHTML='<button class="nav l mut" onclick="cancelEdit()">Cancel</button>'
        +'<div class="mid">'+(draft.isNew?'New Note':'Editing')+'</div>'
        +'<button class="nav r strong" onclick="saveEdit()">Save</button>';
      appEl().className='';
      appEl().innerHTML='<div class="edit">'
        +(draft.isNew?'<input id="nm" class="nminput" placeholder="Note name — e.g. Deploy steps" value="'+escHtml(draft.name||'')+'">':'')
        +mdToolbar()
        +'<textarea id="ta" spellcheck="false"></textarea>'
        +'<div class="hint"><span id="wc"></span>&nbsp;·&nbsp;paste an image to embed it'
        +(draft.isNew?'':'<span class="del" onclick="delNote()">Delete note</span>')+'</div></div>';
      const ta=document.getElementById('ta'); ta.value=draft.body;
      ta.addEventListener('keydown',function(ev){
        if((ev.metaKey||ev.ctrlKey)&&!ev.shiftKey&&!ev.altKey){
          const k=(ev.key||'').toLowerCase();
          if(k==='b'){ ev.preventDefault(); surround('**','**'); }
          else if(k==='i'){ ev.preventDefault(); surround('*','*'); }
          else if(k==='s'){ ev.preventDefault(); saveEdit(); }
        }
      });
      // Pasting an image (or a copied file) embeds it as an attachment instead of doing nothing.
      ta.addEventListener('paste',function(ev){
        const cd=ev.clipboardData;
        if(!cd) return;
        const hasFiles=Array.prototype.some.call(cd.types||[],function(t){return t==='Files';});
        const hasImg=Array.prototype.some.call(cd.items||[],function(it){return it.type&&it.type.indexOf('image/')===0;});
        const hasText=Array.prototype.some.call(cd.types||[],function(t){return t==='text/plain';});
        if((hasFiles||hasImg)&&!hasText){ ev.preventDefault(); send('paste-attach'); }
      });
      ta.addEventListener('input',function(){ updateWC(); draftTick(); });
      const nmEl=document.getElementById('nm');
      if(nmEl) nmEl.addEventListener('input',draftTick);
      updateWC();
      if(draft.isNew){ if(nmEl&&!nmEl.value) nmEl.focus(); else ta.focus(); }
      else ta.focus();
      foot().innerHTML='';
    }
    else if(view==='clips'){
      bar().innerHTML='<button class="nav l" onclick="goHome()">‹ Notes</button>'
        +'<div class="mid">Clipboard</div>'
        +'<button class="nav r mut" onclick="clearClips()">Clear</button>';
      appEl().className='';
      const present={}; CLIPS.forEach(c=>present[c.kind]=1);
      const chips=KINDS.filter(k=>k[0]==='all'||k[0]==='fav'||present[k[0]]).map(function(k){
        return '<div class="chip'+(clipFilter===k[0]?' active':'')+'" onclick="clipFilter=\''+k[0]+'\';route()">'+escHtml(k[1])+'</div>'; }).join('');
      appEl().innerHTML='<div class="chips">'+chips+'</div>'
        +'<input class="search" id="clipq" type="search" placeholder="Search clipboard…" '
        +'oninput="clipSearch=this.value;renderClipList()" value="'+escHtml(clipSearch)+'">'
        +'<div id="cliplist"></div>';
      renderClipList();
      const q=document.getElementById('clipq'); if(clipSearch){ q.focus(); q.setSelectionRange(q.value.length,q.value.length); }
      appEl().scrollTop=0;
      foot().innerHTML='<button class="btn mut" onclick="goHome()">‹ Notes</button>'
        +'<span class="spring"></span><span class="btn mut" style="cursor:default">'+CLIPS.length+' items</span>'
        +'<button class="btn mut" onclick="send(\'quit\')">Quit</button>';
    }
  }
  // ---------- keyboard shortcuts ----------
  document.addEventListener('keydown',function(ev){
    const k=(ev.key||'').toLowerCase();
    if((ev.metaKey||ev.ctrlKey)&&!ev.shiftKey&&!ev.altKey){
      if(k==='n'&&view!=='edit'){ ev.preventDefault(); addNote(); }
      else if(k==='f'){
        if(view==='home'||view==='clips'){ ev.preventDefault();
          const q=document.getElementById(view==='home'?'noteq':'clipq'); if(q) q.focus(); }
      }
    } else if(k==='escape'){
      if(view==='note'){ ev.preventDefault(); goHome(); }
      else if(view==='clips'){ ev.preventDefault(); goHome(); }
      // in the editor Esc is left alone — drafts are preserved anyway
    }
  });
  route();
</script></body></html>
"""#

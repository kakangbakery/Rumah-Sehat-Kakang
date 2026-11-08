<script>
 import {onMount} from 'svelte';
 import {page as route} from '$app/stores';
 import {api} from './auth.js';
 import {openScreen,backScreen} from './navigation.js';
 let entries=[],loading=true,busy=false,error='',message='',form=null;
 const categories={heijo:'SOP Heijo',terapis:'SOP Terapis',customer:'SOP Customer'};
 $: category=$route.url.searchParams.get('sop')||'';
 $: rows=entries.filter(entry=>entry.category===category);
 onMount(load);
 async function load(){loading=true;error='';try{entries=(await api('/sop')).entries;}catch(e){error=e.message;}finally{loading=false;}}
 function edit(entry=null){message='';error='';form=entry?{...entry}:{category,title:'',body:''};}
 async function save(){busy=true;error='';try{await api(form.id?'/sop/'+form.id:'/sop',{method:form.id?'PATCH':'POST',body:JSON.stringify(form)});form=null;await load();message='SOP berhasil disimpan.';}catch(e){error=e.message;}finally{busy=false;}}
 async function remove(entry){if(!window.confirm('Hapus SOP “'+entry.title+'”?'))return;busy=true;error='';try{await api('/sop/'+entry.id,{method:'DELETE',body:JSON.stringify({revision:entry.revision})});await load();message='SOP berhasil dihapus.';}catch(e){error=e.message;}finally{busy=false;}}
</script>
{#if category}
 <button class="back" onclick={()=>backScreen({sop:null})}>← Kembali ke SOP</button>
 <div class="heading"><h2>{categories[category]}</h2><button class="primary" onclick={()=>edit()}>+ Tambah SOP</button></div>
 {#if error}<p class="error" role="alert">{error}</p>{/if}{#if message}<p class="message" role="status">{message}</p>{/if}
 {#if form}<section class="editor"><h3>{form.id?'Edit SOP':'Tambah SOP'}</h3><form onsubmit={e=>{e.preventDefault();save();}}><label>Judul<input required maxlength="150" bind:value={form.title}/></label><label>Isi SOP<textarea required maxlength="20000" rows="10" bind:value={form.body}></textarea></label><div class="actions"><button class="primary" disabled={busy}>{busy?'Menyimpan…':'Simpan'}</button><button type="button" disabled={busy} onclick={()=>form=null}>Batal</button></div></form></section>{/if}
 {#if loading}<p>Memuat SOP…</p>{:else if rows.length===0}<section class="card">Belum ada SOP. Tekan Tambah SOP untuk mulai menulis.</section>{:else}<div class="list">{#each rows as entry}<section class="card"><h3>{entry.title}</h3><p class="body">{entry.body}</p><div class="actions"><button disabled={busy} onclick={()=>edit(entry)}>Edit</button><button disabled={busy} onclick={()=>remove(entry)}>Hapus</button></div></section>{/each}</div>{/if}
{:else}
 <nav class="cards" aria-label="Kategori SOP">{#each Object.entries(categories) as [key,label]}<button onclick={()=>openScreen({sop:key})}>{label}</button>{/each}</nav>
{/if}
<style>
 .cards{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:15px}.cards button,.card,.editor{background:#004b35;color:#f5d47b;border:1px solid #c9a754;border-radius:18px;padding:22px}.cards button{min-height:110px;font-weight:800;font-size:16px;cursor:pointer}.back{background:none;border:0;color:#00543b;font-weight:800;padding:10px 0;margin-bottom:16px;cursor:pointer}.heading{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:20px}.heading h2{color:#064c32;margin:0}.primary{background:#00543b;color:#f5d47b;border:1px solid #c9a754;font-weight:800}.list{display:grid;gap:15px}.card h3,.editor h3{margin:0 0 14px}.body{white-space:pre-wrap;overflow-wrap:anywhere;line-height:1.65}.actions{display:flex;gap:10px}.actions button,button.primary{padding:10px 15px;border-radius:9px;cursor:pointer}.card .actions button,.editor .actions button:not(.primary){background:#fffdf8;color:#004b35;border:1px solid #d0b46b}.editor{margin-bottom:18px}.editor form{display:grid;gap:15px}.editor label{display:grid;gap:8px;font-weight:700}.editor input,.editor textarea{font:inherit;padding:12px;border-radius:9px;border:1px solid #c9a754;color:#123c2b;background:#fff;max-width:100%}.editor textarea{resize:vertical}.error{color:#9b2e19;background:#fff0e8;padding:12px;border-radius:8px}.message{color:#164e30;background:#e8f3e8;padding:12px;border-radius:8px}@media(max-width:500px){.cards{gap:10px}.cards button{min-height:90px;font-size:14px}.heading{flex-wrap:wrap}}
</style>

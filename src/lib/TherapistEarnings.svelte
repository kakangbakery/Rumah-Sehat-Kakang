<script>
 import {page as route} from '$app/stores';
 import {openScreen,backScreen} from './navigation.js';
 import {onMount} from 'svelte';
 import PeriodPicker from './PeriodPicker.svelte';
 import {api} from './auth.js';

 export let admin=false;
 export let onback=()=>{};
 function openTherapist(therapist){return openScreen({therapist:therapist.id},{therapistName:therapist.name});}
 $: selected=admin&&$route.url.searchParams.get('therapist')?{id:$route.url.searchParams.get('therapist'),name:$route.state.therapistName||'Rincian fee terapis'}:null;
 $: selectedId=selected?.id||'';
 let mounted=false;
 $: if(mounted){selectedId;load();}
 let therapists=[];

 const timeZone='Asia/Jakarta';
 const parts=new Intl.DateTimeFormat('en-GB',{year:'numeric',month:'2-digit',timeZone}).formatToParts();
 const currentMonth=parts.find(part=>part.type==='year').value+'-'+parts.find(part=>part.type==='month').value;
 const money=new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0});
 const date=new Intl.DateTimeFormat('id-ID',{dateStyle:'medium',timeZone});
 export let month='';
 let report=null, busy=false, error='',request=0;

 async function load(){
  const currentRequest=++request;
  report=null;
  error='';
  if(!month)return;
  busy=true;
  try{
   const query='?month='+encodeURIComponent(month);
   if(admin && !selected){
    const result=await api('/finance/therapist-fees'+query);
    if(currentRequest===request)therapists=result;
   }else{
    const result=await api(admin?'/finance/therapist-fees'+query+'&therapist='+selected.id :'/therapist/earnings'+query);
    if(currentRequest===request)report=result;
   }
  }catch(e){if(currentRequest===request)error=e.message;}finally{if(currentRequest===request)busy=false;}
 }

 onMount(()=>{if(!month)month=currentMonth;mounted=true;return()=>{mounted=false;request++;};});
</script>

{#if admin}<button class="back" disabled={busy} onclick={()=>selected?backScreen({therapist:null}):onback()}>← {selected?'Daftar terapis':'Keuangan'}</button>{/if}
<PeriodPicker bind:month disabled={busy} onchange={next=>{month=next;load();}}/>
<section aria-label="Pendapatan terapis">
 {#if admin}<h2>{selected?selected.name:'Fee Terapis'}</h2>{/if}
 {#if error}<p role="alert">{error} <button onclick={load}>Coba lagi</button></p>{/if}
 {#if busy}<p role="status">Memuat pendapatan…</p>{/if}
 {#if admin && !selected && !busy && !error}
  {#each therapists as therapist (therapist.id)}
   <button class="therapist" disabled={busy} onclick={()=>openTherapist(therapist)}>{therapist.name}</button>
  {:else}<p>Belum ada terapis dengan reservasi selesai pada periode ini.</p>{/each}
 {/if}
 {#if report}
  <div class="total"><span>Total fee periode</span><strong>{report.rate===null?'—':money.format(report.total)}</strong></div>
  {#if !admin}<div class="row"><span>Kasbon</span><strong>{money.format(0)}</strong></div>
  <div class="row"><span>Bonus</span><strong>{money.format(0)}</strong></div>{/if}
  <h2>Reservasi selesai</h2>
  {#if report.rate===null}
   <p>Pos Fee Terapis belum diterapkan untuk periode ini.</p>
  {:else}
   <p>Fee terapis {report.rate.toLocaleString('id-ID')}%</p>
  {/if}
  {#each report.sessions as session (session.id)}
   <div class="row">
    <span><b>{session.customer}</b><small>{session.service} · {date.format(new Date(session.finished_at))}</small></span>
    <strong>{session.fee===null?'—':money.format(session.fee)}</strong>
   </div>
  {:else}
   <p>Belum ada reservasi selesai pada periode ini.</p>
  {/each}
 {/if}
</section>

<style>
 .back{margin-bottom:18px;min-height:44px;font-weight:750}

 section{background:#fff;border:1px solid #d3ddcd;border-radius:18px;padding:22px;color:#163c2a}
 button{padding:10px 12px;border:1px solid #b9cfba;border-radius:8px;background:#fff;color:#163c2a}
 h2{margin:24px 0 10px;font-size:19px}
 .total,.row{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px}
 .total{border-radius:10px;background:#00543b;color:#fff;padding:15px}
 .row{padding:12px 0;border-bottom:1px solid #e4ecdf}
 .therapist{display:block;width:100%;text-align:left;font-weight:750;margin-top:8px;min-height:44px}
 small{display:block;margin-top:4px}
</style>

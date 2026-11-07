<script>
 import {onMount} from 'svelte';
 import PeriodPicker from './PeriodPicker.svelte';
 import {api} from './auth.js';
 export let simulation=null;
 export let showAllocation=false;
 export let month='';

 const monthParts=new Intl.DateTimeFormat('en-GB',{year:'numeric',month:'2-digit',timeZone:'Asia/Jakarta'}).formatToParts();
 const currentMonth=monthParts.find(part=>part.type==='year').value+'-'+monthParts.find(part=>part.type==='month').value;
 const dateFormat=new Intl.DateTimeFormat('id-ID',{dateStyle:'medium',timeZone:'Asia/Jakarta'});
 const date=day=>dateFormat.format(new Date(day+'T00:00:00+07:00'));
 const currency=new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0});
 const share=(amount,percent)=>Math.floor(amount*Math.round(percent*100)/10000);
 let report=null,busy=false,error='',notice='';
 $: title=showAllocation?'Rincian Pembagian':'Pemasukan';

 onMount(()=>{
  if(!month)month=currentMonth;
  loadReport();
 });

 async function loadReport(){
  busy=true;
  error='';
  report=null;
  try{
   report=await api('/finance/income?month='+encodeURIComponent(month));
  }catch(e){error=e.message;}finally{busy=false;}
 }

 async function apply(){
  if(!simulation||month!==currentMonth||busy)return;
  if(!window.confirm('Terapkan simulasi tersimpan mulai periode bulan ini?'))return;
  busy=true;
  error='';
  notice='';
  try{
   await api('/finance/apply',{method:'POST',body:JSON.stringify({revision:simulation.revision})});
   await loadReport();
   if(!error)notice='Simulasi diterapkan mulai periode bulan ini.';
  }catch(e){error=e.message;}finally{busy=false;}
 }
</script>

<PeriodPicker bind:month disabled={busy} onchange={next=>{month=next;notice='';loadReport();}}/>
<section aria-label={title}>
 <h2>{title}</h2>
 <div class="toolbar">
  {#if !showAllocation && month===currentMonth}
   <button disabled={busy||!simulation||!report} onclick={apply}>Terapkan Simulasi</button>
  {/if}
 </div>
 {#if error}<p role="alert">{error} <button class="retry" onclick={loadReport} disabled={busy}>Coba lagi</button></p>{/if}
 {#if notice}<p role="status">{notice}</p>{/if}
 {#if report}
  <p>{date(report.start)} – {date(report.end)}</p>
  <div class="total">Total periode <strong>{currency.format(report.total)}</strong></div>
  {#if showAllocation}
  <h3>Pembagian yang diterapkan</h3>
  {#each report.items as item}
   <div class="row"><span>{item.name}<small>{item.percent.toLocaleString('id-ID')}%</small></span><strong>{currency.format(share(report.total,item.percent))}</strong></div>
  {:else}<p>Belum ada pos pembagian.</p>{/each}
  <div class="row"><span>Belum terbagi</span><strong>{currency.format(report.total-report.items.reduce((sum,item)=>sum+share(report.total,item.percent),0))}</strong></div>
  {:else}
  <h3>Pemasukan harian</h3>
  {#each report.days as day}
   <div class="row"><span>{date(day.day)}<small>{day.bookings} reservasi selesai</small></span><strong>{currency.format(day.total)}</strong></div>
  {:else}<p>Belum ada reservasi selesai pada periode ini.</p>{/each}
  {/if}
 {:else if busy}<p>Memuat laporan…</p>{/if}
</section>

<style>
 section,.total{background:#004b35!important;color:#f5d47b!important;border-color:#c9a754!important}
 section h2,section h3,section .row,section small,section strong,section span{color:#f5d47b!important}
 section{border:1px solid #d3ddcd;border-radius:18px;background:#fff;padding:22px;color:#163c2a}
 h2{margin:0 0 20px;font-size:19px}
 h3{margin-top:24px;font-size:16px}
 .toolbar,.row,.total{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:12px}
 button{padding:10px 12px;border:1px solid #b9cfba;border-radius:8px}
 button{background:#00543b;color:#fff;font-weight:750;min-height:40px}
 .retry{background:#fff;color:#00543b}
 .row{padding:12px 0;border-bottom:1px solid #e4ecdf}
 .row span{overflow-wrap:anywhere;min-width:0}
 .row small{display:block;margin-top:4px}
 .total{border-radius:10px;background:#ecf5ef;padding:15px}
</style>

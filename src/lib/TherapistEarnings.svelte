<script>
 import {onMount} from 'svelte';
 import {api} from './auth.js';

 const timeZone='Asia/Jakarta';
 const parts=new Intl.DateTimeFormat('en-GB',{year:'numeric',month:'2-digit',timeZone}).formatToParts();
 const currentMonth=parts.find(part=>part.type==='year').value+'-'+parts.find(part=>part.type==='month').value;
 const money=new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0});
 const date=new Intl.DateTimeFormat('id-ID',{dateStyle:'medium',timeZone});
 let month=currentMonth, report=null, busy=false, error='';

 async function load(){
  report=null;
  error='';
  if(!month)return;
  busy=true;
  try{
   report=await api('/therapist/earnings?month='+encodeURIComponent(month));
  }catch(e){error=e.message;}finally{busy=false;}
 }

 onMount(()=>{load();});
</script>

<section aria-label="Pendapatan terapis">
 <label>Periode <input type="month" bind:value={month} max={currentMonth} disabled={busy} onchange={load}/></label>
 {#if error}<p role="alert">{error} <button onclick={load}>Coba lagi</button></p>{/if}
 {#if busy}<p role="status">Memuat pendapatan…</p>{/if}
 {#if report}
  <div class="total"><span>Total fee periode</span><strong>{report.rate===null?'—':money.format(report.total)}</strong></div>
  <div class="row"><span>Kasbon</span><strong>{money.format(0)}</strong></div>
  <div class="row"><span>Bonus</span><strong>{money.format(0)}</strong></div>
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
 section{background:#fff;border:1px solid #d3ddcd;border-radius:18px;padding:22px;color:#163c2a}
 label{display:grid;gap:7px;font-weight:750;margin-bottom:18px}
 input,button{padding:10px 12px;border:1px solid #b9cfba;border-radius:8px;background:#fff;color:#163c2a}
 h2{margin:24px 0 10px;font-size:19px}
 .total,.row{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px}
 .total{border-radius:10px;background:#00543b;color:#fff;padding:15px}
 .row{padding:12px 0;border-bottom:1px solid #e4ecdf}
 small{display:block;margin-top:4px}
</style>

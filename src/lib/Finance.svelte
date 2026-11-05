<script>
 import {onMount} from 'svelte';
 import {api} from './auth.js';

 let view='',saved=null;
 let items=[],revision='',income=0,busy=false,error='',message='';
 const currency=new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0});
 const percentageTotal=rows=>rows.reduce((sum,item)=>sum+Math.round((item.percent??0)*100),0)/100;
 const share=(amount,percent)=>Math.floor(amount*Math.round((percent??0)*100)/10000);
 $: total=percentageTotal(items);
 $: savedRemaining=saved?saved.income-saved.items.reduce((sum,item)=>sum+share(saved.income,item.percent),0):0;
 $: amount=Number.isSafeInteger(income)&&income>=0?income:0;
 $: allocations=items.map(item=>share(amount,item.percent));
 $: remaining=amount-allocations.reduce((sum,value)=>sum+value,0);

 onMount(async()=>{
  try{
   const data=await api('/finance');
   saved=data;
   items=data.items.map(item=>({...item}));
   income=data.income;
   revision=data.revision;
  }catch(e){error=e.message;}
 });

 async function save(){
  error='';
  message='';
  if(!Number.isInteger(income)||income<0||income>2147483647){
   error='Isi nominal simulasi yang valid.';
   return;
  }
  if(total>100||items.some(item=>!item.name.trim()||!Number.isFinite(item.percent)||item.percent<0)){
   error='Isi nama dan persentase tiap pos. Total maksimal 100%.';
   return;
  }
  busy=true;
  try{
   const data=await api('/finance',{method:'PUT',body:JSON.stringify({items,revision,income})});
   saved=data;
   items=data.items.map(item=>({...item}));
   income=data.income;
   revision=data.revision;
   message='Pembagian pemasukan tersimpan.';
  }catch(e){error=e.message;}finally{busy=false;}
 }
</script>

<nav class="finance-menu" aria-label="Menu Keuangan">
 <button class:save={view==='simulation'} aria-pressed={view==='simulation'} onclick={()=>view='simulation'}>Simulasi</button>
 <button class:save={view==='allocation'} aria-pressed={view==='allocation'} onclick={()=>view='allocation'}>Alokasi Dana</button>
</nav>

{#if view==='simulation'}
<section aria-label="Simulasi">
 <h2>Simulasi</h2>
 {#if error}<p class="error" role="alert">{error}</p>{/if}
 {#if message}<p role="status">{message}</p>{/if}
 {#if revision}
  <form onsubmit={e=>{e.preventDefault();save();}}>
   <fieldset disabled={busy}>
    <label class="income">Simulasi pemasukan (Rp)
     <input required type="number" min="0" max="2147483647" step="1" bind:value={income}/>
    </label>
    {#each items as item,i}
     <div class="allocation">
      <label>Pos<input required maxlength="100" bind:value={item.name}/></label>
      <label>Persen<input required type="number" min="0" max="100" step="0.01" bind:value={item.percent}/></label>
      <output>{currency.format(allocations[i])}</output>
      <button type="button" class="remove" aria-label={'Hapus pos '+item.name} onclick={()=>items=items.filter((_,index)=>index!==i)}>Hapus</button>
     </div>
    {/each}
    <div class="totals" class:error={total>100}><strong>Total {total.toLocaleString('id-ID')}%</strong><span>Belum terbagi {currency.format(remaining)}</span></div>
    <div class="actions">
     <button type="button" disabled={items.length>=30} onclick={()=>items=[...items,{name:'',percent:0}]}>Tambah Pos</button>
     <button class="save" disabled={total>100}>{busy?'Menyimpan…':'Simpan Pembagian'}</button>
    </div>
   </fieldset>
  </form>
 {:else if !error}<p>Memuat pembagian pemasukan…</p>{/if}
</section>
{:else if view==='allocation'}
<section aria-label="Alokasi Dana">
 <h2>Alokasi Dana</h2>
 {#if saved}
  <p>Nominal simulasi <strong>{currency.format(saved.income)}</strong></p>
  <dl>
   {#each saved.items as item}
    <div class="summary-row">
     <dt>{item.name} <small>{item.percent.toLocaleString('id-ID')}%</small></dt>
     <dd>{currency.format(share(saved.income,item.percent))}</dd>
    </div>
   {:else}<p>Belum ada pos pembagian.</p>{/each}
  </dl>
  <div class="totals"><strong>Total {percentageTotal(saved.items).toLocaleString('id-ID')}%</strong><span>Belum terbagi {currency.format(savedRemaining)}</span></div>
 {:else if error}<p class="error" role="alert">{error}</p>
 {:else}<p>Memuat alokasi dana…</p>{/if}
</section>
{/if}

<style>
 .finance-menu{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;margin-bottom:20px}
 .finance-menu button{min-height:82px;border-radius:18px}
 .summary-row{display:flex;align-items:baseline;justify-content:space-between;gap:12px;padding:12px 0;border-bottom:1px solid #e4ecdf}
 .summary-row dt{overflow-wrap:anywhere;min-width:0}
 .summary-row small{display:block;margin-top:4px}
 .summary-row dd{margin:0;white-space:nowrap;font-weight:750}

 section{border:1px solid #d3ddcd;border-radius:18px;background:#fff;padding:22px;color:#163c2a}
 h2{margin:0 0 20px;font-size:19px}
 fieldset{border:0;padding:0;margin:0;min-width:0}
 label{display:grid;gap:7px;font-size:13px;font-weight:750}
 input{box-sizing:border-box;width:100%;min-width:0;border:1px solid #c6d4ca;border-radius:9px;padding:11px;color:#163e2c}
 .income{max-width:360px;margin-bottom:16px}
 .allocation{display:grid;grid-template-columns:minmax(0,2fr) minmax(68px,1fr) minmax(110px,1fr) auto;align-items:end;gap:12px;padding:12px 0;border-bottom:1px solid #e4ecdf}
 output{font-weight:750;padding:10px 0}
 button{min-height:40px;border:1px solid #b9cfba;border-radius:8px;padding:8px 12px;background:#fff;color:#00543b;font-weight:750}
 .remove,.error{color:#96391f}
 .save{color:#fff;background:#00543b;border-color:#00543b}
 .actions,.totals{display:flex;flex-wrap:wrap;gap:12px;margin-top:16px;justify-content:space-between}
 @media(max-width:600px){section{padding:16px}.allocation{grid-template-columns:minmax(0,2fr) minmax(70px,1fr);gap:8px}.remove{justify-self:end}}
</style>

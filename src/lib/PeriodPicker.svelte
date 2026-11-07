<script>
 export let month='';
 export let disabled=false;
 export let onchange=()=>{};
 const parts=new Intl.DateTimeFormat('en-GB',{year:'numeric',month:'2-digit',timeZone:'Asia/Jakarta'}).formatToParts();
 const current=parts.find(p=>p.type==='year').value+'-'+parts.find(p=>p.type==='month').value;
 const months=Array.from({length:12},(_,index)=>new Intl.DateTimeFormat('id-ID',{month:'long',timeZone:'Asia/Jakarta'}).format(new Date(Date.UTC(2026,index,1))));
 $: value=month||current;
 $: year=Number(value.slice(0,4));
 $: number=Number(value.slice(5,7));
 $: end=new Date(Date.UTC(year,number,0)).getUTCDate();
 function choose(next){month=next;onchange(next);}
</script>

<div class="period">
 <div class="selection">
  <label class="month">
   <span class="sr-only">Bulan periode</span>
   <select value={value.slice(5,7)} {disabled} onchange={e=>choose(year+'-'+e.currentTarget.value)}>
    {#each months as name,index}<option value={String(index+1).padStart(2,'0')}>Periode {name}</option>{/each}
   </select>
  </label>
  <label class="year">
   <span class="sr-only">Tahun periode</span>
   <select value={year} {disabled} onchange={e=>choose(e.currentTarget.value+'-'+value.slice(5,7))}>
    {#each Array.from({length:100},(_,i)=>2000+i) as y}<option value={y}>{y}</option>{/each}
   </select>
  </label>
 </div>
 <p>1 {months[number-1]} – {end} {months[number-1]} {year}</p>
</div>

<style>
 .period{margin-bottom:24px;color:#00543b}
 .selection{display:flex;align-items:center;gap:6px;flex-wrap:wrap}
 select{max-width:100%;min-height:44px;border:0;background:transparent;color:#00543b;font:inherit;font-size:17px;font-weight:800;padding:6px 20px 6px 0;cursor:pointer}
 select:focus-visible{outline:2px solid #00543b;outline-offset:3px}
 .year select{font-size:15px}
 p{margin:0;color:#4d6357;font-weight:650;font-size:13px}
 .sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
</style>

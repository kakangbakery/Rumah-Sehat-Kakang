<script>
 import {page as route} from '$app/stores';
 import {openScreen,backScreen} from './navigation.js';
 import {onMount} from 'svelte';
 import {goto} from '$app/navigation';
 import {Leaf,LayoutDashboard,CalendarDays,Users,Plus,LogOut,X,Clock,Check,Wallet,Search,RefreshCw,UserRound,ArrowUpRight} from 'lucide-svelte';
 import TherapistEarnings from './TherapistEarnings.svelte';
 import Finance from './Finance.svelte';
 import {supabase,api} from './auth.js';
 import {ROLE_LABEL,ROLE_PATH} from './config.js';
 export let expectedRole;
 let profile=null,loading=true,notice='',failure='',busy=false;
 let appointments=[],accounts=[],services=[],search='',modal=false;
 let staffRole='therapist';
 let therapistModal=false,therapistName='',therapistEmail='',therapistPassword='';
 let pinForm={administrator:'',therapist:'',customer:'',referral:''};
 let serviceForm=null;
 let serviceId='',bookingName='',bookingAddress='',bookingPhone='',bookingDate='',bookingTime='',bookingNotes='';
 let name='',phone='';
 const statusLabel={pending:'Menunggu',confirmed:'Dikonfirmasi',in_progress:'Berlangsung',completed:'Selesai',cancelled:'Dibatalkan'};
 const money=n=>new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0}).format(n);
 const dateText=d=>new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Jakarta',dateStyle:'medium',timeStyle:'short'}).format(new Date(d))+' WIB';
 const initials=n=>(n||'A').split(' ').map(n=>n[0]).slice(0,2).join('').toUpperCase();
 $: page=$route.url.searchParams.get('screen')||'';
 function openPage(next){search='';return openScreen({screen:next,finance:null,therapist:null},{therapistName:null});}
 $: isAdmin=profile?.role==='administrator';
 $: isCustomer=profile?.role==='customer';
 $: isTherapist=profile?.role==='therapist';
 $: isReferral=profile?.role==='referral';
 $: menu=isReferral?[{name:'Profil Saya',icon:UserRound}]:[{name:'Ringkasan',icon:LayoutDashboard},{name:'Reservasi',icon:CalendarDays},isTherapist?{name:'Pendapatan',icon:Wallet}:{name:'Layanan'},...(isAdmin?[{name:'Kelola Akun',icon:Users},{name:'Keuangan',icon:Wallet}]:[]),{name:'Profil Saya',icon:UserRound}];
 $: filtered=appointments.filter(a=>((a.booking_name||a.customer?.full_name||'')+' '+(a.service?.name||'')+' '+(a.therapist?.full_name||'')).toLowerCase().includes(search.toLowerCase()));
 $: therapists=accounts.filter(a=>a.role==='therapist'&&a.active);
 $: visibleAccounts=accounts.filter(a=>(a.full_name+' '+a.email+' '+ROLE_LABEL[a.role]).toLowerCase().includes(search.toLowerCase()));
 onMount(()=>{boot();const {data:{subscription}}=supabase.auth.onAuthStateChange(event=>{if(event==='SIGNED_OUT'){profile=null;appointments=[];accounts=[];goto('/');}});const sync=()=>{if(document.visibilityState==='visible')boot(false);};document.addEventListener('visibilitychange',sync);return()=>{subscription.unsubscribe();document.removeEventListener('visibilitychange',sync);};});
 async function boot(initial=true){if(initial)loading=true;failure='';try{
  const result=await api('/me');
  if(result.profile.role!==expectedRole){window.location.replace(ROLE_PATH[result.profile.role]);return;}
  profile=result.profile;name=profile.full_name;phone=profile.phone;
  if(profile.role!=='referral')await loadData();
 }catch(e){failure=e.message;if(e.status===401||e.status===403||e.message.includes('login')){profile=null;appointments=[];accounts=[];await goto('/',{replaceState:true});}}finally{loading=false;}}
 async function loadData(){const r=await Promise.all([api('/appointments'),api('/services'),...(profile.role==='administrator'?[api('/accounts')]:[])]);appointments=r[0].appointments;services=r[1].services;if(r[2])accounts=r[2].accounts;}
 async function act(action,message){busy=true;failure='';notice='';try{await action();await boot(false);notice=message;}catch(e){failure=e.message;if(e.status===401||e.status===403)await boot(false);}finally{busy=false;}}
 async function logout(){busy=true;try{const {error}=await supabase.auth.signOut();if(error)throw error;profile=null;appointments=[];accounts=[];await goto('/');}catch{failure='Keluar belum berhasil. Coba lagi.';}finally{busy=false;}}
 function closeTherapistForm(){
  therapistModal=false;
  therapistName='';
  therapistEmail='';
  therapistPassword='';
 }
 function addTherapist(){
  act(async()=>{
   await api(staffRole==='referral'?'/accounts/referrals':'/accounts/therapists',{method:'POST',body:JSON.stringify({
    full_name:therapistName,email:therapistEmail,initial_password:therapistPassword
   })});
   closeTherapistForm();
   search='';
  },'Akun '+ROLE_LABEL[staffRole]+' berhasil dibuat.');
 }
 function editService(service){
  failure='';
  serviceForm=service
   ?{id:service.id,name:service.name,price:service.price,duration_minutes:service.duration_minutes}
   :{id:null,name:'',price:undefined,duration_minutes:undefined};
 }
 function saveService(){
  const {id,...fields}=serviceForm;
  act(async()=>{
   await api(id?'/services/'+id:'/services',{method:id?'PATCH':'POST',body:JSON.stringify(fields)});
   serviceForm=null;
  },'Layanan berhasil disimpan.');
 }
 function deleteService(service){
  if(!window.confirm('Hapus layanan "'+service.name+'" dari katalog?'))return;
  act(()=>api('/services/'+service.id,{method:'DELETE'}),'Layanan berhasil dihapus.');
 }
 function openBooking(){
  serviceId=services[0]?.id||'';
  bookingName=isCustomer?(profile.full_name?.trim()||profile.email):'';
  bookingAddress='';
  bookingPhone=isCustomer?(profile.phone||''):'';
  bookingDate='';
  bookingTime='';
  bookingNotes='';
  modal=true;
 }
 async function saveBooking(){
  if(!bookingDate||!bookingTime)return;
  await act(async()=>{
   await api('/appointments',{method:'POST',body:JSON.stringify({
    service_id:serviceId,starts_at:bookingDate+'T'+bookingTime+'+07:00',
    booking_name:bookingName,booking_address:bookingAddress,
    booking_phone:bookingPhone,booking_notes:bookingNotes
   })});
   modal=false;
  },'Reservasi tersimpan. Administrator akan menentukan terapis.');
 }
 function changeStatus(id,status){act(()=>api('/appointments/'+id+'/status',{method:'PATCH',body:JSON.stringify({status})}),'Status sesi diperbarui.');}
 function assign(id,therapistId){if(therapistId)act(()=>api('/appointments/'+id+'/therapist',{method:'PATCH',body:JSON.stringify({therapist_id:therapistId})}),'Terapis ditugaskan.');}
 function updateAccount(a,role,active){if(role==='administrator'&&a.role!=='administrator'&&!window.confirm('Berikan akses administrator kepada '+a.email+'? Akun ini dapat mengelola akun lain dan seluruh reservasi.'))return;act(()=>api('/accounts/'+a.id,{method:'PATCH',body:JSON.stringify({role,active})}),'Hak akses akun diperbarui.');}
 function savePins(){const pins=Object.fromEntries(Object.entries(pinForm).filter(([,pin])=>pin));if(!Object.keys(pins).length){failure='Isi minimal satu PIN yang ingin diubah.';return;}if(Object.values(pins).some(pin=>!/^\d{6}$/.test(pin))){failure='PIN harus tepat 6 angka.';return;}act(async()=>{await api('/access-pins',{method:'PATCH',body:JSON.stringify({pins})});pinForm={administrator:'',therapist:'',customer:'',referral:''};},'PIN portal berhasil diperbarui.');}
 function saveProfile(){act(()=>api('/me',{method:'PATCH',body:JSON.stringify({full_name:name,phone})}),'Profil berhasil disimpan.');}
</script>
<svelte:head><title>Dashboard {ROLE_LABEL[expectedRole]} — HEIJO Reflexology</title><meta name="robots" content="noindex,nofollow"/></svelte:head>
{#if loading}<div class="loading"><Leaf size={38}/><h1>Menyiapkan dashboard…</h1><p>Memeriksa sesi dan hak akses Anda.</p></div>{:else if !profile}<div class="loading"><h1>Login diperlukan</h1><p>{failure||'Masuk untuk melanjutkan.'}</p><a href="/">Ke halaman login</a></div>{:else}
<div class="top-band" aria-hidden="true"></div>
<div class="app"><main>
{#if !page}<header class="account-head">
 <div class="identity"><div class="identity-copy"><a class="brand-name" href={ROLE_PATH[profile.role]} aria-label="HEIJO Reflexology"></a><div class="account-role">{ROLE_LABEL[profile.role]}</div><p class="account-name">{profile.full_name||'Akun Saya'}</p></div></div>
 <div class="account-actions">{#if !isReferral}<button class="icon-button" onclick={()=>{openPage('Reservasi');}} aria-label="Cari reservasi"><Search size={23}/></button>{/if}<button class="icon-button refresh" disabled={busy} onclick={()=>act(async()=>{},'Data diperbarui.')} aria-label="Perbarui data"><RefreshCw size={22}/></button><button class="exit-button" disabled={busy} onclick={logout}><LogOut size={17}/><span>Keluar</span></button></div>
</header>{/if}<div class="content" class:finance-screen={!!page}>
{#if !page}<nav class="menu-grid" aria-label="Menu utama">{#each menu as item}<button class:active={page===item.name} aria-pressed={page===item.name} onclick={()=>{openPage(item.name);}}>{#if item.icon}<item.icon size={23}/>{/if}<span>{item.name}</span></button>{/each}</nav>{/if}
{#if page && page!=='Keuangan'}<button class="feature-back" onclick={()=>{backScreen({screen:null,finance:null,therapist:null});}}>← Kembali</button>
<div class="heading"><div><p class="eyebrow">HEIJO REFLEXOLOGY</p><h1>{page==='Ringkasan'?'Selamat datang, '+(profile.full_name||'Kakang'):page}<span class="gold">.</span></h1></div>{#if page==='Reservasi'&&!isTherapist}<button class="primary" onclick={openBooking}><Plus size={18}/>Reservasi baru</button>{:else if page==='Layanan'&&isAdmin}<button class="primary" onclick={()=>editService(null)}><Plus size={18}/>Tambah Layanan</button>{:else if page==='Kelola Akun'&&isAdmin}<button class="primary" onclick={()=>{failure='';staffRole='therapist';therapistModal=true;}}><Plus size={18}/>Tambah Terapis</button><button class="primary" onclick={()=>{failure='';staffRole='referral';therapistModal=true;}}><Plus size={18}/>Tambah Referral</button>{/if}</div>{/if}
{#if failure}<div class="notice error" role="alert">{failure}<button onclick={()=>failure=''} aria-label="Tutup pesan"><X size={16}/></button></div>{/if}{#if notice}<div class="notice" role="status">{notice}<button onclick={()=>notice=''} aria-label="Tutup pesan"><X size={16}/></button></div>{/if}
{#if page==='Ringkasan'}{#if isCustomer}<section class="welcome"><div><span class="pill">JEDA SEJENAK, NYAMAN KEMBALI</span><h2>Lepas lelah. Temukan nyaman.</h2><button onclick={()=>openPage('Reservasi')}>Lihat reservasi <ArrowUpRight size={17}/></button></div><Leaf class="hero-leaf" size={160} strokeWidth={0.8}/></section>{/if}<div class="stats"><article><span>Reservasi{isCustomer?' saya':''}</span><strong>{appointments.length}</strong></article><article><span>Menunggu</span><strong>{appointments.filter(a=>a.status==='pending').length}</strong></article><article><span>Sedang berlangsung</span><strong>{appointments.filter(a=>a.status==='in_progress').length}</strong></article><article><span>Selesai</span><strong>{appointments.filter(a=>a.status==='completed').length}</strong></article></div>{/if}
{#if page==='Ringkasan'||page==='Reservasi'}<section class="panel"><div class="panel-heading"><div><h2>{isTherapist?'Penugasan saya':isCustomer?'Reservasi saya':'Daftar reservasi'}</h2></div><span class="muted">{appointments.length} sesi</span></div><div class="search"><Search size={18}/><input bind:value={search} placeholder="Cari pelanggan atau layanan…" aria-label="Cari reservasi"/></div><div class="table-wrap"><table><thead><tr>{#if !isCustomer}<th>PELANGGAN</th>{/if}<th>LAYANAN & JADWAL</th><th>TERAPIS</th><th>STATUS</th><th>AKSI</th></tr></thead><tbody>{#each filtered as a}<tr>{#if !isCustomer}<td><strong>{a.booking_name||a.customer?.full_name||'Customer'}</strong><small>{a.booking_phone||a.customer?.phone||'Nomor belum diisi'}</small>{#if a.booking_address}<small class="booking-detail">{a.booking_address}</small>{/if}</td>{/if}<td><strong>{a.service?.name||'Layanan refleksi'}</strong><small>{dateText(a.starts_at)}</small>{#if a.booking_notes}<small class="booking-detail">{a.booking_notes}</small>{/if}<small>{a.duration_minutes} menit · {money(a.price)}</small></td><td>{a.therapist?.full_name||'Belum ditugaskan'}</td><td><span class={'status '+a.status}>{statusLabel[a.status]}</span></td><td><div class="actions">{#if isAdmin && ['pending','confirmed'].includes(a.status)}<select aria-label={'Tugaskan terapis untuk '+(a.booking_name||a.customer?.full_name||'customer')} disabled={busy} value={a.therapist_id||''} onchange={e=>assign(a.id,e.currentTarget.value)}><option value="" disabled>Pilih terapis</option>{#each therapists as t}<option value={t.id}>{t.full_name||t.email}</option>{/each}</select>{/if}{#if a.status==='pending' && a.therapist_id && (isAdmin || (isTherapist && a.therapist_id===profile.id))}<button class="outline" disabled={busy} onclick={()=>changeStatus(a.id,'confirmed')}>Konfirmasi</button>{/if}{#if a.status==='confirmed' && !isCustomer}<button class="outline" disabled={busy} onclick={()=>changeStatus(a.id,'in_progress')}>Mulai sesi</button>{/if}{#if a.status==='in_progress' && !isCustomer}<button class="outline" disabled={busy} onclick={()=>changeStatus(a.id,'completed')}><Check size={15}/>Selesai</button>{/if}{#if isAdmin && !['completed','cancelled'].includes(a.status)}<button class="danger-link" disabled={busy} onclick={()=>changeStatus(a.id,'cancelled')}>Batalkan</button>{/if}{#if isCustomer}<span class="muted">{a.status==='pending'?'Menunggu admin':'Lihat status sesi'}</span>{/if}</div></td></tr>{:else}<tr><td colspan={isCustomer?4:5}><div class="empty"><CalendarDays size={31}/><h3>Belum ada reservasi</h3><p>{search?'Tidak ada data yang cocok.':isTherapist?'Sesi yang ditugaskan admin akan muncul di sini.':'Reservasi yang dibuat akan muncul di sini.'}</p></div></td></tr>{/each}</tbody></table></div></section>{/if}
{#if page==='Pendapatan' && isTherapist}<TherapistEarnings/>{/if}
{#if page==='Layanan' && !isTherapist}<div class="service-grid">{#each services as s}<section class="panel service-card"><h2>{s.name}</h2><div class="duration"><Clock size={16}/>{s.duration_minutes} menit</div><strong>{money(s.price)}</strong>{#if isAdmin}<div class="actions"><button class="outline" disabled={busy} onclick={()=>editService(s)}>Edit</button><button class="outline service-delete" disabled={busy} onclick={()=>deleteService(s)}>Hapus</button></div>{/if}</section>{/each}</div>{/if}
{#if page==='Kelola Akun'&&isAdmin}<section class="pin-panel"><div><p class="eyebrow">KEAMANAN MASUK</p><h2>Atur PIN 6 Angka</h2><p>Biarkan kosong jika PIN akun tersebut tidak ingin diubah.</p></div><form onsubmit={e=>{e.preventDefault();savePins();}}>{#each [['administrator','Admin'],['therapist','Terapis'],['customer','Customer'],['referral','Referral']] as item}<label>{item[1]}<input type="password" inputmode="numeric" maxlength="6" autocomplete="new-password" placeholder="PIN baru 6 angka" bind:value={pinForm[item[0]]}/></label>{/each}<button class="gold-button" disabled={busy}>{busy?'Menyimpan…':'Simpan PIN'}</button></form></section><section class="panel"><div class="search"><Search size={18}/><input bind:value={search} placeholder="Cari nama, email, atau peran…" aria-label="Cari akun"/></div><div class="table-wrap"><table><thead><tr><th>AKUN</th><th>PERAN</th><th>STATUS</th><th>AKSES</th></tr></thead><tbody>{#each visibleAccounts as a}<tr><td><strong>{a.full_name||'Nama belum diisi'}</strong><small>{a.email}</small></td><td>{#if a.id===profile.id}<span class="role-badge">Administrator</span>{:else}<select class="role-select" aria-label={'Peran '+a.email} value={a.role} disabled={busy} onchange={e=>updateAccount(a,e.currentTarget.value,a.active)}><option value="customer">Customer</option><option value="therapist">Terapis</option><option value="referral">Referral</option><option value="administrator">Administrator</option></select>{/if}</td><td><span class="status" class:completed={a.active} class:cancelled={!a.active}>{a.active?'Aktif':'Nonaktif'}</span></td><td>{#if a.id!==profile.id}<button class="outline" disabled={busy} onclick={()=>updateAccount(a,a.role,!a.active)}>{a.active?'Nonaktifkan':'Aktifkan'}</button>{:else}<span class="muted">Akun Anda dilindungi</span>{/if}</td></tr>{:else}<tr><td colspan="4" class="empty">Tidak ada akun yang cocok.</td></tr>{/each}</tbody></table></div></section>{/if}
{#if page==='Keuangan'&&isAdmin}<Finance onback={()=>backScreen({screen:null,finance:null,therapist:null})}/>{/if}
{#if page==='Profil Saya'}<section class="panel profile-panel"><h2>Profil saya</h2><p class="muted">Peran: <strong>{ROLE_LABEL[profile.role]}</strong></p><form onsubmit={e=>{e.preventDefault();saveProfile();}}><label>Email<input value={profile.email} disabled/></label><label>Nama lengkap<input required maxlength="100" bind:value={name} autocomplete="name"/></label><label>Nomor WhatsApp<input maxlength="25" type="tel" pattern="[+0-9 ()-]*" bind:value={phone} autocomplete="tel"/></label><button class="primary" disabled={busy}>{busy?'Menyimpan…':'Simpan profil'}</button></form></section>{/if}
{#if !page}<footer><span>© 2026 HEIJO Reflexology</span><span>Saatnya melepas lelah.</span></footer>{/if}</div></main></div>
{#if serviceForm && isAdmin}
<div class="overlay" role="presentation">
 <div class="modal" role="dialog" aria-modal="true" aria-labelledby="service-title" tabindex="-1">
  <div class="panel-heading">
   <h2 id="service-title">{serviceForm.id?'Edit Layanan':'Tambah Layanan'}</h2>
   <button type="button" disabled={busy} onclick={()=>serviceForm=null} aria-label="Tutup formulir"><X size={22}/></button>
  </div>
  {#if failure}<div class="notice error" role="alert">{failure}</div>{/if}
  <form onsubmit={e=>{e.preventDefault();saveService();}}>
   <label>Nama layanan<input required maxlength="100" bind:value={serviceForm.name}/></label>
   <label>Harga (Rp)<input required type="number" min="0" max="2147483647" step="1" bind:value={serviceForm.price}/></label>
   <label>Durasi (menit)<input required type="number" min="1" max="1440" step="1" bind:value={serviceForm.duration_minutes}/></label>
   <button class="primary" disabled={busy}>{busy?'Menyimpan…':'Simpan Layanan'}</button>
  </form>
 </div>
</div>
{/if}
{#if therapistModal && isAdmin}
<div class="overlay" role="presentation">
 <div class="modal" role="dialog" aria-modal="true" aria-labelledby="therapist-title" tabindex="-1">
  <div class="panel-heading">
   <h2 id="therapist-title">Tambah {ROLE_LABEL[staffRole]}</h2>
   <button type="button" disabled={busy} onclick={closeTherapistForm} aria-label="Tutup formulir"><X size={22}/></button>
  </div>
  {#if failure}<div class="notice error" role="alert">{failure}</div>{/if}
  <form onsubmit={e=>{e.preventDefault();addTherapist();}}>
   <label>Nama lengkap<input required maxlength="100" bind:value={therapistName}/></label>
   <label>Email akun<input placeholder={profile.is_demo?"nama@kakang.test":undefined} required type="email" maxlength="254" autocomplete="off" bind:value={therapistEmail}/></label>
   <label>Password awal<input required type="password" minlength="8" maxlength="72" autocomplete="new-password" bind:value={therapistPassword}/></label>
   <button class="primary" disabled={busy}>{busy?'Menyimpan…':'Simpan '+ROLE_LABEL[staffRole]}</button>
  </form>
 </div>
</div>
{/if}
{#if modal}<div class="overlay" role="presentation"><div class="modal" role="dialog" aria-modal="true" aria-labelledby="booking-title" tabindex="-1"><div class="panel-heading"><div><p class="eyebrow">RESERVASI REFLEKSI</p><h2 id="booking-title">Jadwalkan waktu Anda</h2></div><button onclick={()=>modal=false} aria-label="Tutup formulir"><X size={22}/></button></div>{#if failure}<div class="notice error" role="alert">{failure}</div>{/if}<form onsubmit={e=>{e.preventDefault();saveBooking();}}><label>Nama<input required maxlength="100" bind:value={bookingName} readonly={isCustomer}/></label>
<label>Alamat<textarea required maxlength="500" rows="2" bind:value={bookingAddress}></textarea></label>
<label>Nomor Telepon<input required type="tel" maxlength="25" bind:value={bookingPhone}/></label>
<label>Layanan<select required bind:value={serviceId}>{#each services as s}<option value={s.id}>{s.name} · {money(s.price)}</option>{/each}</select></label><label>Tanggal<input required type="date" bind:value={bookingDate}/></label>
<label>Jam (WIB)<input required type="time" bind:value={bookingTime}/></label>
<label>Keterangan<textarea maxlength="1000" rows="2" bind:value={bookingNotes}></textarea></label>
<div class="booking-total"><span>Harga layanan</span><strong>{money(services.find(s=>s.id===serviceId)?.price||0)}</strong></div><button class="primary" disabled={busy||!services.length}>{busy?'Menyimpan…':'Simpan reservasi'}</button></form></div></div>{/if}
{/if}
<style>
 .stats article,.panel{background:#004b35!important;color:#f5d47b!important;border-color:#c9a754!important}
 .stats article>span,.stats strong,.panel-heading h2,.panel .muted,.panel td,.panel td small,.panel label,.service-card h2,.service-card>strong,.duration,.profile-panel h2,.panel .empty,.panel .empty :global(svg){color:#f5d47b!important}
 .panel th{color:#f5d47b!important;background:#003c2a!important}.panel td{border-color:#c9a75455}.panel .search{color:#f5d47b}
:global(*){box-sizing:border-box}:global(body){margin:0;background:#f8f5ef;color:#0c3928;font-family:Arial,Helvetica,sans-serif;font-size:15px}:global(button),:global(input),:global(select){font:inherit}:global(button){cursor:pointer}:global(button:disabled){opacity:.55;cursor:wait}:global(button:focus-visible),:global(a:focus-visible){outline:3px solid #b48929;outline-offset:4px}button{border:0;background:none;color:inherit}input,select{padding:12px;border:1px solid #c6d4ca;border-radius:10px;background:#fff;color:#163e2c;font-size:14px;max-width:100%}input:focus,select:focus{outline:2px solid #087655;outline-offset:2px}.top-band{height:24px;background:linear-gradient(115deg,#002f22,#006245 55%,#004632);border-bottom:3px solid transparent;border-image:linear-gradient(90deg,#88651d,#ffe5a0,#b18529,#f5d37b) 1}.app{min-height:calc(100vh - 24px);background:radial-gradient(ellipse at 0 0,#e8dfc633,transparent 40%)}main{width:100%}.content{max-width:1080px;margin:auto;padding:38px 30px 22px}.account-head{display:flex;align-items:center;justify-content:space-between;gap:20px;margin-bottom:30px}.identity{display:flex;align-items:center;gap:18px;min-width:0}.account-role{display:flex;gap:8px;align-items:center;color:#34583f;font-size:12px;font-weight:750;margin-top:15px}.account-name{font-size:22px;font-weight:750;color:#143c29;margin:7px 0 0;line-height:1.25;overflow-wrap:anywhere}.account-actions{display:flex;gap:10px;align-items:center}.icon-button,.exit-button{height:48px;border:1px solid #d1d7cb;background:#fff;box-shadow:0 2px 7px #283b2505;border-radius:14px;color:#004c35;display:flex;align-items:center;justify-content:center;gap:8px;font-size:13px;font-weight:800}.icon-button{width:48px}.exit-button{padding:0 17px}.menu-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:15px;margin-bottom:30px}.menu-grid button{min-height:110px;position:relative;display:flex;align-items:center;justify-content:center;gap:12px;padding:20px 15px;border-radius:21px;border:1px solid #d5dacd;background:#fff;color:#004b34;font-size:16px;font-weight:800;box-shadow:0 3px 8px #13382403;transition:background .15s,box-shadow .15s,transform .15s}.menu-grid button:hover{border-color:#a88a3c;box-shadow:0 5px 18px #0039250c;transform:translateY(-1px)}.menu-grid button.active{background:radial-gradient(ellipse at 100% 0,#24755566,transparent 65%),linear-gradient(120deg,#006346,#003b2a);color:#fff;border-color:#b89239;box-shadow:0 7px 20px #00402b18}.menu-grid button.active::before{content:'';position:absolute;top:0;left:25px;right:25px;height:2px;background:linear-gradient(90deg,transparent,#ffdf8c,transparent);border-radius:20px}.heading{display:flex;justify-content:space-between;align-items:center;gap:20px;margin-bottom:22px}.eyebrow{font-size:10px;letter-spacing:1.6px;font-weight:800;color:#785b22;margin:0 0 12px}h1{font-size:29px;font-weight:800;letter-spacing:-.7px;line-height:1.3;margin:0;color:#093d2b}.gold{color:#9f7622}.primary{display:flex;align-items:center;justify-content:center;gap:9px;background:linear-gradient(115deg,#006246,#003e2b);border:1px solid #b38c36;color:#fff;padding:13px 17px;font-size:13px;font-weight:800;border-radius:11px;white-space:nowrap}.primary:hover{background:#003b29}.notice{display:flex;justify-content:space-between;gap:12px;font-size:12px;line-height:1.7;padding:12px 16px;margin-bottom:20px;border:1px solid #cadfce;border-radius:12px;background:#eaf2e9;color:#244d32}.error{background:#ffede5;border-color:#e3b9a8;color:#8a2c18}.welcome{position:relative;overflow:hidden;display:flex;justify-content:space-between;align-items:center;gap:25px;border-radius:22px;border:1px solid #c4a052;padding:31px 34px;background:radial-gradient(ellipse at 100% 100%,#b38b2b55,transparent 60%),linear-gradient(130deg,#005c40,#002f22);color:white}.welcome::before{content:'';position:absolute;top:0;left:22px;right:22px;height:2px;background:linear-gradient(90deg,transparent,#ffdf90,transparent)}.pill{font-size:10px;letter-spacing:1.4px;font-weight:800;color:#ffe1a0}.welcome h2{font-size:31px;line-height:1.25;letter-spacing:-.8px;max-width:580px;margin:20px 0 13px;color:#fff}.welcome button{display:flex;gap:12px;align-items:center;color:#ffdfa0;font-size:13px;font-weight:800;padding:10px 0}.welcome :global(.hero-leaf){color:#e6c16c;flex-shrink:0;opacity:.75;transform:rotate(-20deg)}.stats{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px;margin:22px 0}.stats article{background:#fff;border:1px solid #d5dfd0;border-radius:17px;padding:23px}.stats article>span{font-size:12px;color:#365b42;font-weight:750}.stats strong{display:block;font-size:31px;font-weight:800;color:#005038;margin:15px 0 10px}.panel{border:1px solid #d3ddcd;border-radius:18px;background:#fff;overflow:hidden}.panel-heading{display:flex;align-items:center;justify-content:space-between;gap:15px;padding:23px}.panel-heading h2{font-size:18px;font-weight:800;color:#073e2a;margin:0}.muted{font-size:12px;line-height:1.7;color:#3e604a}.search{display:flex;align-items:center;gap:10px;margin:0 23px 18px;color:#245b3e}.search input{width:100%;font-size:13px;background:#f9fbf6}.table-wrap{overflow:auto}table{width:100%;border-collapse:collapse;text-align:left;white-space:nowrap}th{background:#edf3ea;color:#2b5339;padding:14px 18px;font-size:10px;font-weight:850;letter-spacing:.6px}td{padding:19px 18px;border-bottom:1px solid #e4ecdf;font-size:13px;line-height:1.6;color:#163c2a}td strong{font-weight:800}td small{display:block;font-size:11px;color:#3c6048;margin-top:5px}.status{display:inline-block;padding:6px 9px;font-size:11px;font-weight:750;background:#f2eee1;color:#6f541b;border-radius:6px}.status.confirmed{background:#e5f1e9;color:#225b39}.status.in_progress{background:#fff0c5;color:#72520c}.status.completed{background:#e3f4e6;color:#205a32}.status.cancelled{background:#fdeae2;color:#893a23}.actions{display:flex;align-items:center;gap:9px}.actions select{font-size:12px;max-width:170px}.outline{display:flex;align-items:center;justify-content:center;gap:8px;padding:9px 12px;font-size:12px;font-weight:750;border:1px solid #b9cfba;border-radius:7px;color:#1c5535;background:#fff}.danger-link{font-size:11px;color:#96391f;font-weight:750}.empty{text-align:center;color:#355d42;padding:30px}.empty :global(svg){color:#387452}.empty h3{font-size:16px}.empty p{font-size:13px;white-space:normal}.role-badge{display:inline-flex;padding:6px 9px;font-size:11px;font-weight:750;color:#005037;border:1px solid #bdd3bd;border-radius:5px;background:#edf6ea}.service-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:17px}.service-card{padding:27px}.service-card h2{font-size:23px;line-height:1.3;color:#064c32;margin-top:0}.duration{display:flex;align-items:center;gap:9px;font-size:13px;color:#3b6548;margin:20px 0}.service-card>strong{font-size:24px;font-weight:800;color:#064d31;display:block;margin:22px 0}.profile-panel{padding:28px;max-width:600px}.profile-panel h2{font-size:24px;margin:0 0 14px;color:#06482e}.profile-panel form{margin-top:25px}form{display:grid;gap:18px}label{display:grid;gap:9px;font-size:13px;font-weight:750;color:#214b32}label input,label select{width:100%;padding:13px;font-size:14px}.profile-panel input:disabled{color:#375c45;background:#edf2e9}.overlay{position:fixed;inset:0;z-index:50;background:#002b1f88;backdrop-filter:blur(4px);display:flex;align-items:center;justify-content:center;padding:20px}.modal{background:#fffdf8;border:1px solid #d1af65;border-radius:19px;padding:25px;max-height:95vh;width:470px;overflow:auto}.modal .panel-heading{padding:0 0 8px}.modal h2{font-size:23px}.modal form{margin-top:24px}.booking-total{display:flex;justify-content:space-between;font-size:14px;padding:10px 0;color:#174a30}.modal form>.primary{width:100%}footer{display:flex;justify-content:space-between;gap:12px;font-size:11px;line-height:1.8;color:#3e6147;padding-top:30px}.loading{min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px;padding:30px;text-align:center}.loading h1{font-size:26px}.loading p{font-size:14px;color:#315c43}.loading a{color:#005237;font-weight:800}
@media(max-width:760px){.top-band{height:20px}.content{padding:26px 16px 20px}.account-head{gap:10px;margin-bottom:24px}.identity{gap:11px}.account-role{font-size:10px;margin-top:11px;gap:6px}.account-name{font-size:18px;margin-top:5px}.account-actions{gap:7px}.icon-button{width:40px;height:43px;border-radius:13px}.exit-button{height:43px;padding:0 11px;font-size:12px;border-radius:13px}.exit-button :global(svg){display:none}.refresh{display:none}.menu-grid{gap:10px;margin-bottom:27px}.menu-grid button{min-height:90px;padding:16px 9px;border-radius:18px;font-size:14px;gap:8px}.menu-grid button :global(svg){width:19px;height:19px}.heading{align-items:flex-start;flex-wrap:wrap;gap:16px}h1{font-size:25px}.eyebrow{font-size:9px}.primary{font-size:13px}.welcome{padding:25px 23px;border-radius:18px}.welcome h2{font-size:28px}.welcome :global(.hero-leaf){display:none}.stats{grid-template-columns:1fr 1fr;gap:11px;margin:18px 0}.stats article{padding:18px}.stats strong{font-size:29px}.panel-heading{padding:20px 16px}.panel-heading h2{font-size:17px}.search{margin:0 16px 15px}th,td{padding:14px}.service-grid{grid-template-columns:1fr}.service-card{padding:25px}.profile-panel{padding:23px}.modal{padding:22px}footer{flex-wrap:wrap;font-size:10px}}@media(max-width:370px){.account-name{font-size:16px}.identity{gap:9px}.account-actions{gap:5px}.icon-button{width:36px}.exit-button{padding:0 9px}.menu-grid button{font-size:13px}}

th,.role-badge,.role-select {
  background: #00543b;
  color: #fff;
  font-weight: 800;
}
.role-badge,.role-select {
  border: 1px solid #00543b;
}
.role-select option {
  background: #fff;
  color: #123c2b;
}
.panel > .search:first-child {
  margin-top: 18px;
}
.service-delete{color:#96391f;border-color:#e3b9a8}
label textarea{width:100%;padding:13px;border:1px solid #c6d4ca;border-radius:10px;font:inherit;color:#163e2c;resize:vertical}.booking-detail{white-space:pre-wrap;max-width:240px;overflow-wrap:anywhere}
.brand-name{display:block;width:100%;aspect-ratio:3.5;background:#004326 url('/heijo-gold.jpg') center 52% / 220% auto no-repeat;border-radius:7px;text-decoration:none;width:clamp(112px,34vw,165px)}

.top-band{display:none}
.account-head{background:#004326;padding:24px max(16px,calc((100vw - 1020px)/2));margin:0;border-bottom:2px solid #c7a247;gap:12px}
.account-role,.account-name{color:#fff}
.account-role{margin-top:12px}
.account-head .icon-button,.account-head .exit-button{background:#ffffff0d;border-color:#d8bd6a88;color:#fff;box-shadow:none}
.brand-name{background-size:220% auto;background-position:center 50%;border-radius:0}
@media(max-width:760px){.account-head{padding:22px 16px}.account-name{font-size:18px}.account-role{font-size:12px}.brand-name{width:clamp(124px,37vw,180px)}}
.finance-screen{min-height:100dvh;padding-top:20px}
.feature-back{min-height:44px;margin-bottom:20px;font-weight:750;color:#00543b;padding:10px 0}
.menu-grid button{background:linear-gradient(135deg,#006346,#003c2a);border-color:#c9a754;color:#f5cf72;box-shadow:0 6px 16px #003d2a22}.menu-grid button:hover{border-color:#f2d57f}.menu-grid button :global(svg){color:#f5cf72}.stats article,.panel,.service-card,.profile-panel{border-color:#c9a754}.pin-panel{display:grid;grid-template-columns:1fr 1.4fr;gap:22px;margin-bottom:20px;padding:25px;border-radius:18px;background:linear-gradient(135deg,#006346,#003c2a);border:1px solid #c9a754;color:#f5cf72}.pin-panel h2{margin:0;font-size:21px;color:#f5cf72}.pin-panel p:not(.eyebrow){font-size:12px;line-height:1.7;color:#e8f1e8}.pin-panel form{grid-template-columns:1fr 1fr;gap:12px}.pin-panel label{color:#f5cf72;font-size:12px}.pin-panel input{border-color:#d4b462}.gold-button{grid-column:span 2;border:1px solid #f1d27b;border-radius:9px;background:#f5cf72;color:#004326;font-weight:800;padding:12px}@media(max-width:760px){.pin-panel{grid-template-columns:1fr}.pin-panel form{grid-template-columns:1fr}.gold-button{grid-column:auto}}
</style>

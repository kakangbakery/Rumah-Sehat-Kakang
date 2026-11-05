import {randomUUID} from 'node:crypto';
import express from 'express';
import {rateLimit} from 'express-rate-limit';
import {createClient} from '@supabase/supabase-js';
import {SUPABASE_URL,SUPABASE_KEY} from '../src/lib/config.js';

const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function allowRoles(...roles){return (req,res,next)=>roles.includes(req.profile?.role)?next():res.status(403).json({error:'Anda tidak memiliki akses ke fitur ini.'});}
const safeError=(res,error)=>res.status(error?.code==='42501'?403:400).json({error:({PGRST116:'Data tidak ditemukan.','42501':'Akses ditolak.'})[error?.code]||'Data tidak dapat disimpan. Periksa jadwal, peran akun, dan status reservasi.'});
export function createApp({makeClient=(token)=>createClient(SUPABASE_URL,SUPABASE_KEY,{global:{headers:{Authorization:'Bearer '+token}},auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}}),limiter=true}={}){
 const app=express();
 app.disable('x-powered-by');
 if(process.env.VERCEL) app.set('trust proxy',1);
 app.use((_req,res,next)=>{res.set('Cache-Control','no-store');res.set('X-Content-Type-Options','nosniff');next();});
 app.use(express.json({limit:'16kb'}));
 app.get('/api/health',(_req,res)=>res.json({status:'ok',application:'refleksi-kakang',mode:'rbac'}));
 if(limiter)app.use('/api',rateLimit({windowMs:60000,limit:120,standardHeaders:'draft-8',legacyHeaders:false,message:{error:'Terlalu banyak permintaan. Coba lagi sebentar.'}}));
 app.use('/api',async(req,res,next)=>{
  const token=req.headers.authorization?.match(/^Bearer (\S+)$/i)?.[1];
  if(!token)return res.status(401).json({error:'Silakan login terlebih dahulu.'});
  try{
   const db=makeClient(token);
   const {data,error}=await db.auth.getUser(token);
   if(error||!data.user||!data.user.email_confirmed_at)return res.status(401).json({error:'Sesi tidak valid atau email belum diverifikasi. Silakan login kembali.'});
   const profileResult=await db.from('profiles').select('id,email,full_name,phone,role,active,is_demo').eq('id',data.user.id).single();
   if(profileResult.error||!profileResult.data?.active)return res.status(403).json({error:'Akun belum aktif atau akses dinonaktifkan. Hubungi administrator.'});
   req.db=db;req.profile=profileResult.data;next();
  }catch{res.status(503).json({error:'Layanan login sementara tidak tersedia.'});}
 });
 app.get('/api/me',(req,res)=>res.json({profile:req.profile}));
 app.patch('/api/me',async(req,res)=>{
  const {full_name,phone}=req.body||{};
  if(typeof full_name!=='string'||!full_name.trim()||full_name.length>100||typeof phone!=='string'||phone.length>25||!/^[+\d ()-]*$/.test(phone))return res.status(400).json({error:'Nama atau nomor telepon tidak valid.'});
  const {error}=await req.db.from('profiles').update({full_name:full_name.trim(),phone}).eq('id',req.profile.id);
  if(error)return safeError(res,error);res.json({ok:true});
 });
 async function saveService(req,res){
  const {name,price,duration_minutes}=req.body||{};
  if(typeof name!=='string'||!name.trim()||name.trim().length>100
   ||!Number.isInteger(price)||price<0||price>2147483647
   ||!Number.isInteger(duration_minutes)||duration_minutes<1||duration_minutes>1440){
   return res.status(400).json({error:'Isi nama, harga dalam rupiah, dan durasi 1–1440 menit.'});
  }
  const fields={name:name.trim(),price,duration_minutes};
  const id=req.params.id;
  if(id&&!uuid.test(id))return res.status(400).json({error:'Layanan tidak valid.'});
  const query=id
   ?req.db.from('services').update(fields).eq('id',id)
   :req.db.from('services').insert({...fields,is_demo:req.profile.is_demo});
  const {data,error}=await query.select('id').maybeSingle();
  if(error?.code==='23505')return res.status(409).json({error:'Nama layanan sudah digunakan.'});
  if(error)return safeError(res,error);
  if(!data)return res.status(404).json({error:'Layanan tidak ditemukan.'});
  return res.status(id?200:201).json({id:data.id});
 }
 app.post('/api/services',allowRoles('administrator'),saveService);
 app.patch('/api/services/:id',allowRoles('administrator'),saveService);
 app.delete('/api/services/:id',allowRoles('administrator'),async(req,res)=>{
  if(!uuid.test(req.params.id))return res.status(400).json({error:'Layanan tidak valid.'});
  const {data,error}=await req.db.rpc('archive_service',{service_id:req.params.id});
  if(error)return safeError(res,error);
  if(!data)return res.status(404).json({error:'Layanan tidak ditemukan.'});
  res.json({ok:true});
 });
 app.get('/api/services',async(req,res)=>{
  const {data,error}=await req.db.from('services').select('id,name,duration_minutes,price,description').eq('active',true).eq('is_demo',req.profile.is_demo).order('price');
  if(error)return safeError(res,error);res.json({services:data});
 });
 app.get('/api/appointments',async(req,res)=>{
  // RLS restricts both the main rows and joined customer/therapist profiles.
  const {data,error}=await req.db.from('appointments').select('id,customer_id,therapist_id,starts_at,duration_minutes,price,status,booking_name,booking_address,booking_phone,booking_notes,service:services(name),customer:profiles!appointments_customer_id_fkey(full_name,phone),therapist:profiles!appointments_therapist_id_fkey(full_name)').order('starts_at',{ascending:false}).limit(300);
  if(error)return safeError(res,error);res.json({appointments:data});
 });
 app.post('/api/appointments',allowRoles('administrator','customer'),async(req,res)=>{
  const {service_id,starts_at,customer_id,booking_name,booking_address,booking_phone,booking_notes}=req.body||{};
  const selfBooking=req.profile.role==='customer';
  const customerId=selfBooking?req.profile.id:(customer_id??null);
  const parsed=Date.parse(starts_at);
  if(!uuid.test(service_id)||(customerId!==null&&!uuid.test(customerId))||!Number.isFinite(parsed)||parsed<=Date.now()){
   return res.status(400).json({error:'Pilih layanan dan waktu reservasi yang akan datang.'});
  }
  const contact={};
  const hasDetails=customerId===null||[booking_name,booking_address,booking_phone,booking_notes].some(value=>value!==undefined);
  if(hasDetails){
   const name=selfBooking?(req.profile.full_name?.trim()||req.profile.email):booking_name;
   if(typeof name!=='string'||!name.trim()||name.trim().length>100
    ||typeof booking_address!=='string'||!booking_address.trim()||booking_address.trim().length>500
    ||typeof booking_phone!=='string'||booking_phone.trim().length>25
    ||!/^[+\d ()-]+$/.test(booking_phone.trim())||booking_phone.replace(/\D/g,'').length<7
    ||(booking_notes!==undefined&&(typeof booking_notes!=='string'||booking_notes.trim().length>1000))){
    return res.status(400).json({error:'Lengkapi nama, alamat, dan nomor telepon yang valid.'});
   }
   Object.assign(contact,{booking_name:name.trim(),booking_address:booking_address.trim(),
    booking_phone:booking_phone.trim(),booking_notes:booking_notes?.trim()||null});
  }
  const {data,error}=await req.db.from('appointments').insert({
   service_id,starts_at:new Date(parsed).toISOString(),customer_id:customerId,...contact
  }).select('id').single();
  if(error)return safeError(res,error);res.status(201).json({appointment:data});
 });
 app.patch('/api/appointments/:id/status',allowRoles('administrator','therapist'),async(req,res)=>{
  if(!uuid.test(req.params.id)||!['pending','confirmed','in_progress','completed','cancelled'].includes(req.body?.status))return res.status(400).json({error:'Status tidak valid.'});
  const {data,error}=await req.db.from('appointments').update({status:req.body.status}).eq('id',req.params.id).select('id');
  if(error)return safeError(res,error);if(!data?.length)return res.status(404).json({error:'Reservasi tidak ditemukan atau bukan penugasan Anda.'});res.json({ok:true});
 });
 app.get('/api/accounts',allowRoles('administrator'),async(req,res)=>{
  const {data,error}=await req.db.from('profiles').select('id,email,full_name,phone,role,active,created_at').order('created_at',{ascending:false}).limit(500);
  if(error)return safeError(res,error);res.json({accounts:data});
 });
 async function createStaff(req,res){
  const {full_name,email,initial_password}=req.body||{};
  if([full_name,email,initial_password].some(value=>typeof value!=='string')){
   return res.status(400).json({error:'Isi nama, email, dan password awal.'});
  }
  const {data,error}=await req.db.rpc(req.path.endsWith('/referrals')?'create_referral':'create_therapist',{full_name,email,initial_password});
  if(error?.code==='23505')return res.status(409).json({error:'Email tidak tersedia. Gunakan email lain.'});
  if(error?.code==='22023')return res.status(400).json({error:'Periksa nama dan email. Password minimal 8 karakter dan maksimal 72 byte. Akun demo memakai email @kakang.test.'});
  if(error)return safeError(res,error);
  res.status(201).json({id:data});
 }
 app.post('/api/accounts/therapists',allowRoles('administrator'),createStaff);
 app.post('/api/accounts/referrals',allowRoles('administrator'),createStaff);
 app.patch('/api/accounts/:id',allowRoles('administrator'),async(req,res)=>{
  if(!uuid.test(req.params.id)||!['administrator','therapist','customer','referral'].includes(req.body?.role)||typeof req.body?.active!=='boolean')return res.status(400).json({error:'Peran atau status akun tidak valid.'});
  const {error}=await req.db.rpc('manage_account',{target_id:req.params.id,new_role:req.body.role,is_active:req.body.active});
  if(error)return safeError(res,error);res.json({ok:true});
 });
 app.patch('/api/appointments/:id/therapist',allowRoles('administrator'),async(req,res)=>{
  if(!uuid.test(req.params.id)||!uuid.test(req.body?.therapist_id))return res.status(400).json({error:'Pilih terapis yang valid.'});
  const {error}=await req.db.rpc('assign_therapist',{appointment_id:req.params.id,new_therapist_id:req.body.therapist_id});
  if(error)return safeError(res,error);res.json({ok:true});
 });
 app.get('/api/finance',allowRoles('administrator'),async(req,res)=>{
  const {data,error}=await req.db.from('finance_allocations').select('items,revision,income').single();
  if(error)return safeError(res,error);
  res.json(data);
 });
 app.put('/api/finance',allowRoles('administrator'),async(req,res)=>{
  const {items,revision,income}=req.body||{};
  if(!uuid.test(revision)||!Array.isArray(items))return res.status(400).json({error:'Pembagian pemasukan tidak valid.'});
  if(income!==undefined&&(!Number.isInteger(income)||income<0||income>2147483647))return res.status(400).json({error:'Nominal simulasi tidak valid.'});
  const changes={items,revision:randomUUID()};
  if(income!==undefined)changes.income=income;
  const {data,error}=await req.db.from('finance_allocations')
   .update(changes).eq('revision',revision).select('items,revision,income').maybeSingle();
  if(error?.code==='23514')return res.status(400).json({error:'Periksa nama pos dan persentase. Total maksimal 100%.'});
  if(error)return safeError(res,error);
  if(!data)return res.status(409).json({error:'Pembagian sudah berubah. Muat ulang halaman sebelum menyimpan.'});
  res.json(data);
 });
 app.get('/api/finance/income',allowRoles('administrator'),async(req,res)=>{
  const month=req.query.month;
  if(typeof month!=='string'||!/^20[0-9]{2}-(0[1-9]|1[0-2])$/.test(month)){
   return res.status(400).json({error:'Pilih periode yang valid.'});
  }
  const {data,error}=await req.db.rpc('finance_income_report',{month_start:month+'-01'});
  if(error)return safeError(res,error);
  res.json(data);
 });
 app.get('/api/therapist/earnings',allowRoles('therapist'),async(req,res)=>{
  const month=req.query.month;
  if(typeof month!=='string'||!/^20[0-9]{2}-(0[1-9]|1[0-2])$/.test(month)){
   return res.status(400).json({error:'Pilih periode yang valid.'});
  }
  const {data,error}=await req.db.rpc('therapist_earnings',{month_start:month+'-01'});
  if(error)return safeError(res,error);
  res.json(data);
 });
 app.get('/api/finance/therapist-fees',allowRoles('administrator'),async(req,res)=>{
  const {month,therapist}=req.query;
  if(typeof month!=='string'||!/^20[0-9]{2}-(0[1-9]|1[0-2])$/.test(month)){
   return res.status(400).json({error:'Pilih periode yang valid.'});
  }
  if(therapist!==undefined&&(typeof therapist!=='string'||!uuid.test(therapist))){
   return res.status(400).json({error:'Pilih terapis yang valid.'});
  }
  const {data,error}=await req.db.rpc('admin_therapist_fees',{month_start:month+'-01',target:therapist??null});
  if(error)return safeError(res,error);
  res.json(data);
 });
 app.post('/api/finance/apply',allowRoles('administrator'),async(req,res)=>{
  if(!uuid.test(req.body?.revision))return res.status(400).json({error:'Simpan simulasi terlebih dahulu.'});
  const {data,error}=await req.db.rpc('apply_finance_simulation',{expected_revision:req.body.revision});
  if(error)return safeError(res,error);
  if(!data)return res.status(409).json({error:'Simulasi sudah berubah. Muat ulang halaman sebelum menerapkan.'});
  res.json({ok:true});
 });
 app.get('/api/role-audit',allowRoles('administrator'),async(req,res)=>{
  const {data,error}=await req.db.from('role_audit').select('*').order('created_at',{ascending:false}).limit(100);
  if(error)return safeError(res,error);res.json({audit:data});
 });
 app.use('/api',(_req,res)=>res.status(404).json({error:'Endpoint tidak ditemukan.'}));
 app.use((error,_req,res,_next)=>res.status(error.status===413?413:400).json({error:'Format permintaan tidak valid.'}));
 return app;
}
export const app=createApp();
export default app;

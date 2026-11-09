import test from 'node:test';
import assert from 'node:assert/strict';
import {createApp} from '../server/app.js';
const userId='11111111-1111-4111-8111-111111111111';
function fakeClient(token){
 const role=['administrator','therapist','customer'].includes(token)?token:'customer';
 return {auth:{getUser:async()=>({data:{user:token==='invalid'?null:{id:userId,email_confirmed_at:new Date().toISOString()}},error:token==='invalid'?new Error():null})},rpc:async(name,args)=>({data:name==='checkout_products'&&args.cart.length?userId:null,error:null}),from(table){return {select(){return this;},insert(){return this;},update(){return this;},eq(){return this;},order(){return this;},limit(){return Promise.resolve({data:[],error:null});},maybeSingle:async()=>({data:{id:userId},error:null}),single:async()=>({data:{id:userId,role,active:token!=='inactive'},error:null})};}};
}
async function withServer(fn){const server=createApp({makeClient:fakeClient,limiter:false}).listen(0);await new Promise(r=>server.once('listening',r));try{await fn('http://127.0.0.1:'+server.address().port);}finally{await new Promise(r=>server.close(r));}}
const request=(url,path,token,options={})=>fetch(url+path,{...options,headers:{...(token?{Authorization:'Bearer '+token}:{}),'Content-Type':'application/json'}});
test('API fails closed without credentials, invalid token, and inactive profile',()=>withServer(async url=>{
 for(const [token,status] of [[null,401],['invalid',401],['inactive',403]]) assert.equal((await request(url,'/api/me',token)).status,status);
}));
test('customer and therapist cannot call admin account, assignment, or audit endpoints',()=>withServer(async url=>{
 for(const role of ['customer','therapist']){
  for(const path of ['/api/accounts','/api/role-audit'])assert.equal((await request(url,path,role)).status,403);
  assert.equal((await request(url,'/api/accounts/'+userId,role,{method:'PATCH',body:JSON.stringify({role:'administrator',active:true})})).status,403);
  assert.equal((await request(url,'/api/appointments/'+userId+'/therapist',role,{method:'PATCH',body:JSON.stringify({therapist_id:userId})})).status,403);
 }
}));
test('customer cannot alter session status; therapist cannot create reservations',()=>withServer(async url=>{
 assert.equal((await request(url,'/api/appointments/'+userId+'/status','customer',{method:'PATCH',body:'{"status":"completed"}'})).status,403);
 assert.equal((await request(url,'/api/appointments','therapist',{method:'POST',body:'{}'})).status,403);
}));
test('verified administrator can list accounts; identity comes from live profile',()=>withServer(async url=>{
 assert.equal((await request(url,'/api/accounts','administrator')).status,200);
 const r=await request(url,'/api/me','customer');assert.equal((await r.json()).profile.role,'customer');
}));
test('invalid appointment parameters and oversized/malformed bodies are rejected',()=>withServer(async url=>{
 assert.equal((await request(url,'/api/appointments','customer',{method:'POST',body:'{}'})).status,400);
 assert.equal((await request(url,'/api/me','customer',{method:'PATCH',body:'{bad json'})).status,400);
 assert.equal((await request(url,'/api/me','customer',{method:'PATCH',body:JSON.stringify({full_name:'a'.repeat(20000),phone:''})})).status,413);
}));
test('catalog writes and product orders are limited to the correct roles',()=>withServer(async url=>{
 assert.equal((await request(url,'/api/catalog','customer',{method:'POST',body:'{}'})).status,403);
 assert.equal((await request(url,'/api/catalog/'+userId,'customer',{method:'DELETE',body:'{}'})).status,403);
 assert.equal((await request(url,'/api/product-orders','customer')).status,403);
 assert.equal((await request(url,'/api/product-orders','therapist',{method:'POST',body:'{}'})).status,403);
 assert.equal((await request(url,'/api/catalog','administrator',{method:'POST',body:JSON.stringify({name:'Madu',price:-1,description:'',image:''})})).status,400);
}));
test('administrator can add a catalog item and customer can submit a cart',()=>withServer(async url=>{
 const p=await request(url,'/api/catalog','administrator',{method:'POST',body:JSON.stringify({name:'Madu',price:60000,description:'Madu',image:''})});assert.equal(p.status,201);
 const o=await request(url,'/api/product-orders','customer',{method:'POST',body:JSON.stringify({customer_name:'Pembeli',phone:'081234567890',address:'Alamat',cart:[{id:userId,quantity:2,price:60000}]})});assert.equal(o.status,201);assert.equal((await o.json()).id,userId);
}));

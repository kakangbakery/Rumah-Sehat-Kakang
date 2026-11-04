import {createClient} from '@supabase/supabase-js';
import {SUPABASE_URL,SUPABASE_KEY} from './config.js';
export const supabase=createClient(SUPABASE_URL,SUPABASE_KEY);
export async function api(path,options={}){
 const {data:{session}}=await supabase.auth.getSession();
 if(!session) throw new Error('Silakan login terlebih dahulu.');
 const response=await fetch('/api'+path,{...options,headers:{'Content-Type':'application/json',Authorization:'Bearer '+session.access_token,...options.headers}});
 const result=await response.json();
 if(!response.ok){const e=new Error(result.error||'Permintaan tidak berhasil.');e.status=response.status;throw e;}
 return result;
}

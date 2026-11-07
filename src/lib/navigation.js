import {goto} from '$app/navigation';
import {page} from '$app/stores';
import {get} from 'svelte/store';

export function openScreen(changes, metadata={}){
 const current=get(page);
 const url=new URL(current.url);
 for(const [key,value] of Object.entries(changes)){
  if(value===null||value==='')url.searchParams.delete(key);
  else url.searchParams.set(key,value);
 }
 if(url.href===current.url.href)return;
 return goto(url,{
  state:{...current.state,...metadata,heijoDepth:(current.state.heijoDepth||0)+1}
 });
}

export function backScreen(fallback){
 const current=get(page);
 if(current.state.heijoDepth>0){
  window.history.back();
  return;
 }
 const url=new URL(current.url);
 for(const [key,value] of Object.entries(fallback)){
  if(value===null||value==='')url.searchParams.delete(key);
  else url.searchParams.set(key,value);
 }
 return goto(url,{replaceState:true,state:{heijoDepth:0}});
}

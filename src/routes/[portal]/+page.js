import {error} from '@sveltejs/kit';
export function load({params}){
 const roles={administrator:'administrator',terapis:'therapist',customer:'customer',referral:'referral'};
 if(!roles[params.portal])error(404,'Halaman tidak ditemukan');
 return {expectedRole:roles[params.portal]};
}

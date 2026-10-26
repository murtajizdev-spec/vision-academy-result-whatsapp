import {createClient} from '@supabase/supabase-js';
import crypto from 'node:crypto';
export const config={api:{bodyParser:false}};
async function raw(req){const chunks=[];for await(const c of req)chunks.push(c);return Buffer.concat(chunks)}
export default async function handler(req,res){
 if(req.method==='GET'){
  if(req.query['hub.mode']==='subscribe'&&req.query['hub.verify_token']===process.env.WHATSAPP_VERIFY_TOKEN)return res.status(200).send(req.query['hub.challenge']);
  return res.status(403).end();
 }
 if(req.method!=='POST')return res.status(405).end();
 const body=await raw(req),sig=req.headers['x-hub-signature-256']||'',appSecret=process.env.WHATSAPP_APP_SECRET;
 if(!appSecret)return res.status(503).end();
 const expected='sha256='+crypto.createHmac('sha256',appSecret).update(body).digest('hex');
 if(sig.length!==expected.length||!crypto.timingSafeEqual(Buffer.from(sig),Buffer.from(expected)))return res.status(403).end();
 let payload;try{payload=JSON.parse(body.toString())}catch{return res.status(400).end()}
 const db=createClient(process.env.SUPABASE_URL,process.env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});
 for(const entry of payload.entry||[])for(const change of entry.changes||[])for(const s of change.value?.statuses||[]){
  if(!['sent','delivered','read','failed'].includes(s.status))continue;
  await db.from('message_queue').update({status:s.status,last_error:s.errors?.[0]?.message||null}).eq('provider_message_id',s.id);
 }
 return res.status(200).json({ok:true});
}

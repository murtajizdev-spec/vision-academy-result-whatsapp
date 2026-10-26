// Vercel serverless endpoint. Schedule with an external cron service or Vercel Cron.
// Uses Meta-approved templates only; does not send the arbitrary message body as a template.
import {createClient} from '@supabase/supabase-js';
export default async function handler(req,res){
 if(req.method!=='GET'&&req.method!=='POST')return res.status(405).json({error:'Method not allowed'});
 const secret=process.env.CRON_SECRET;
 if(!secret||req.headers.authorization!==`Bearer ${secret}`)return res.status(401).json({error:'Unauthorized'});
 const {SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,WHATSAPP_ACCESS_TOKEN,WHATSAPP_PHONE_NUMBER_ID,WHATSAPP_TEMPLATE_LANGUAGE='en'}=process.env;
 if(!SUPABASE_URL||!SUPABASE_SERVICE_ROLE_KEY||!WHATSAPP_ACCESS_TOKEN||!WHATSAPP_PHONE_NUMBER_ID)return res.status(503).json({error:'Server-side Cloud API setup incomplete'});
 const db=createClient(SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});
 const {data:messages,error}=await db.from('message_queue').select('id,phone,template_name,consent_confirmed,status').eq('status','queued').eq('consent_confirmed',true).lte('scheduled_for',new Date().toISOString()).limit(20);
 if(error)return res.status(500).json({error:'Queue unavailable'});
 let sent=0,failed=0;
 for(const m of messages){
  if(!/^[a-z0-9_]{1,512}$/.test(m.template_name||'')||!/^\d{10,15}$/.test(m.phone)){await db.from('message_queue').update({status:'failed',last_error:'Invalid phone or template'}).eq('id',m.id);failed++;continue}
  // Claim atomically to reduce duplicate sends across concurrent invocations.
  const {data:claimed}=await db.from('message_queue').update({status:'sending'}).eq('id',m.id).eq('status','queued').select('id');
  if(!claimed?.length)continue;
  try{
   const response=await fetch(`https://graph.facebook.com/v22.0/${WHATSAPP_PHONE_NUMBER_ID}/messages`,{method:'POST',headers:{Authorization:`Bearer ${WHATSAPP_ACCESS_TOKEN}`,'Content-Type':'application/json'},body:JSON.stringify({messaging_product:'whatsapp',to:m.phone,type:'template',template:{name:m.template_name,language:{code:WHATSAPP_TEMPLATE_LANGUAGE}}})});
   const result=await response.json();
   if(!response.ok)throw Error(JSON.stringify(result).slice(0,400));
   await db.from('message_queue').update({status:'sent',provider_message_id:result.messages?.[0]?.id||null,sent_at:new Date().toISOString(),last_error:null}).eq('id',m.id);sent++;
  }catch(e){await db.from('message_queue').update({status:'failed',last_error:String(e.message).slice(0,400)}).eq('id',m.id);failed++}
 }
 return res.status(200).json({processed:sent+failed,sent,failed});
}

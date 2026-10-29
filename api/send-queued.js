// Vercel cron: server-only credentials, Meta-approved templates, consent required.
import {createClient} from '@supabase/supabase-js';
export default async function handler(req,res){
 if(!['GET','POST'].includes(req.method))return res.status(405).json({error:'Method not allowed'});
 const secret=process.env.CRON_SECRET;
 if(!secret||req.headers.authorization!==`Bearer ${secret}`)return res.status(401).json({error:'Unauthorized'});
 const {SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,WHATSAPP_ACCESS_TOKEN,WHATSAPP_PHONE_NUMBER_ID}=process.env;
 if(!SUPABASE_URL||!SUPABASE_SERVICE_ROLE_KEY||!WHATSAPP_ACCESS_TOKEN||!WHATSAPP_PHONE_NUMBER_ID)return res.status(503).json({error:'WhatsApp server configuration incomplete'});
 const db=createClient(SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});
 const {data:messages,error}=await db.from('message_queue').select('id,phone,template_name,template_language,template_parameters,consent_confirmed').eq('status','queued').eq('consent_confirmed',true).lte('scheduled_for',new Date().toISOString()).order('scheduled_for',{ascending:true}).limit(20);
 if(error)return res.status(500).json({error:'Queue query failed'});
 let sent=0,failed=0;
 for(const m of messages||[]){
  const validPhone=/^\d{10,15}$/.test(m.phone||'');const validName=/^[a-z0-9_]{1,512}$/.test(m.template_name||'');
  const params=m.template_parameters;
  const validParams=Array.isArray(params)&&params.length<=10&&params.every(p=>typeof p==='string'&&p.length<=1024);
  const {data:claim,error:claimError}=await db.from('message_queue').update({status:'sending'}).eq('id',m.id).eq('status','queued').select('id');
  if(claimError||!claim?.length)continue;
  if(!validPhone||!validName||!validParams){await db.from('message_queue').update({status:'failed',last_error:'Invalid phone, template or parameters'}).eq('id',m.id);failed++;continue}
  const template={name:m.template_name,language:{code:m.template_language||'en'}};
  if(params.length)template.components=[{type:'body',parameters:params.map(text=>({type:'text',text}))}];
  try{
   const response=await fetch(`https://graph.facebook.com/${process.env.WHATSAPP_GRAPH_VERSION||'v22.0'}/${WHATSAPP_PHONE_NUMBER_ID}/messages`,{method:'POST',headers:{Authorization:`Bearer ${WHATSAPP_ACCESS_TOKEN}`,'Content-Type':'application/json'},body:JSON.stringify({messaging_product:'whatsapp',to:m.phone,type:'template',template})});
   const result=await response.json();
   if(!response.ok||!result.messages?.[0]?.id)throw Error(JSON.stringify(result).slice(0,400));
   await db.from('message_queue').update({status:'sent',provider_message_id:result.messages[0].id,sent_at:new Date().toISOString(),last_error:null}).eq('id',m.id);sent++;
  }catch(e){await db.from('message_queue').update({status:'failed',last_error:String(e.message).slice(0,400)}).eq('id',m.id);failed++}
 }
 return res.status(200).json({processed:sent+failed,sent,failed});
}

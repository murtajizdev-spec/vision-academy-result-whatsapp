import fs from 'node:fs';
import path from 'node:path';
import ts from '/opt/nvm/versions/node/v22.16.0/lib/node_modules/typescript/lib/typescript.js';
const root=process.cwd();let failed=false;
for(const file of fs.readdirSync(path.join(root,'src')).filter(f=>f.endsWith('.jsx'))){
 const source=fs.readFileSync(path.join(root,'src',file),'utf8');
 const result=ts.transpileModule(source,{fileName:file,reportDiagnostics:true,compilerOptions:{jsx:ts.JsxEmit.ReactJSX,target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}});
 const errs=result.diagnostics?.filter(d=>d.category===ts.DiagnosticCategory.Error)||[];
 if(errs.length){failed=true;for(const e of errs)console.error(file,ts.flattenDiagnosticMessageText(e.messageText,' '))}else console.log('JSX syntax OK',file);
}
for(const file of fs.readdirSync(path.join(root,'api')).filter(f=>f.endsWith('.js'))){
 const source=fs.readFileSync(path.join(root,'api',file),'utf8');
 const parsed=ts.createSourceFile(file,source,ts.ScriptTarget.ES2022,true,ts.ScriptKind.JS);
 if(parsed.parseDiagnostics.length){failed=true;console.error(file,parsed.parseDiagnostics.map(e=>e.messageText))}else console.log('API syntax OK',file)
}
const sql=fs.readFileSync(path.join(root,'supabase/upgrade_v5_4_security_automation.sql'),'utf8');
for(const needle of ['v54_marks_insert_guard','v54_marks_update_guard','v54_parent_marks_select','v54_message_insert','v54_access_audit','v54_published']){
 if(!sql.includes(needle)){failed=true;console.error('Missing SQL security control',needle)}
}
if(failed)process.exit(1);
console.log('Static checks passed. Database integration and Vite build require dependencies and a staging Supabase project.');

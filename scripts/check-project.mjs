import fs from 'node:fs';
const required=['src/main.jsx','src/SeriesStudio.jsx','src/V3.jsx','src/V4.jsx','src/V5.jsx','src/style.css','supabase/upgrade_existing_to_unified.sql','supabase/upgrade_v5_2_series.sql'];
for(const f of required){if(!fs.existsSync(f)){console.error('Missing '+f);process.exitCode=1}else console.log('OK '+f)}
if(!process.exitCode)console.log('Project files present. This is NOT a production build test.');

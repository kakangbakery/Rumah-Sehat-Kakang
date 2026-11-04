import express from 'express';
export const app = express();
app.disable('x-powered-by');
app.use(express.json({limit:'32kb'}));
app.get('/api/health', (_req,res)=>res.json({status:'ok',application:'refleksi-kakang',mode:'frontend-preview'}));
// Database endpoints are intentionally unavailable until authentication is implemented.
app.use('/api', (_req,res)=>res.status(404).json({error:'Endpoint belum tersedia'}));
export default app;

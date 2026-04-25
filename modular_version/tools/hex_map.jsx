import { useState, useRef, useEffect, useCallback } from "react";

// Exact coordinates from seed.sql (manually placed, Lübeck = 0,0)
const CITIES = [
  {name:"Lubeck",         q:  0, r:  0, league:"Hanseatic",    region:"Baltic",       terrain:"coast", pop:18206},
  {name:"Hamburg",        q: -1, r:  0, league:"Hanseatic",    region:"West",         terrain:"coast", pop:34771},
  {name:"Rostock",        q:  1, r:  0, league:"Hanseatic",    region:"Baltic",       terrain:"coast", pop:20764},
  {name:"Stettin",        q:  3, r:  1, league:"Hanseatic",    region:"Baltic",       terrain:"coast", pop:29761},
  {name:"Gdansk",         q:  6, r: -1, league:"Hanseatic",    region:"Baltic",       terrain:"coast", pop:33318},
  {name:"Riga",           q:  9, r: -4, league:"Hanseatic",    region:"Baltic",       terrain:"coast", pop:17026},
  {name:"Reval",          q: 10, r: -7, league:"Hanseatic",    region:"Baltic",       terrain:"coast", pop:7480},
  {name:"Novgorod",       q: 15, r: -6, league:"Hanseatic",    region:"East",         terrain:"land",  pop:27462},
  {name:"Stockholm",      q:  5, r: -7, league:"Hanseatic",    region:"Baltic",       terrain:"coast", pop:21820},
  {name:"Visby",          q:  5, r: -5, league:"Hanseatic",    region:"Baltic",       terrain:"coast", pop:7258},
  {name:"Malmo",          q:  2, r: -2, league:"Hanseatic",    region:"Baltic",       terrain:"coast", pop:24759},
  {name:"Torun",          q:  6, r:  1, league:"Hanseatic",    region:"Baltic",       terrain:"land",  pop:15944},
  {name:"Bergen",         q: -4, r: -8, league:"Hanseatic",    region:"North Sea",    terrain:"coast", pop:12006},
  {name:"Oslo",           q:  0, r: -7, league:"Hanseatic",    region:"North Sea",    terrain:"coast", pop:19206},
  {name:"Aalborg",        q: -1, r: -4, league:"Hanseatic",    region:"North Sea",    terrain:"coast", pop:26660},
  {name:"Ribe",           q: -1, r: -2, league:"Hanseatic",    region:"North Sea",    terrain:"coast", pop:8961},
  {name:"Scarborough",    q: -8, r:  0, league:"Hanseatic",    region:"British",      terrain:"coast", pop:17423},
  {name:"Edinburgh",      q:-10, r: -3, league:"Hanseatic",    region:"British",      terrain:"coast", pop:23061},
  {name:"London",         q: -8, r:  3, league:"Hanseatic",    region:"British",      terrain:"coast", pop:42914},
  {name:"Brugge",         q: -5, r:  3, league:"Hanseatic",    region:"West",         terrain:"coast", pop:93884},
  {name:"Groningen",      q: -3, r:  1, league:"Hanseatic",    region:"West",         terrain:"land",  pop:16558},
  {name:"Bremen",         q: -1, r:  1, league:"Hanseatic",    region:"West",         terrain:"land",  pop:17612},
  {name:"Cologne",        q: -3, r:  4, league:"Hanseatic",    region:"Rhine",        terrain:"land",  pop:25084},
  {name:"Ladoga",         q: 15, r: -7, league:"Hanseatic",    region:"East",         terrain:"land",  pop:10329},
  {name:"Venice",         q:  1, r: 10, league:"Mediterranean",region:"Mediterranean",terrain:"coast", pop:116000},
  {name:"Genoa",          q: -1, r: 11, league:"Mediterranean",region:"Mediterranean",terrain:"coast", pop:148000},
  {name:"Marseille",      q: -4, r: 13, league:"Mediterranean",region:"Mediterranean",terrain:"coast", pop:46358},
  {name:"Barcelona",      q: -6, r: 15, league:"Mediterranean",region:"Mediterranean",terrain:"coast", pop:60681},
  {name:"Lisbon",         q:-14, r: 18, league:"Mediterranean",region:"Atlantic",     terrain:"coast", pop:53345},
  {name:"Constantinople", q: 13, r: 15, league:"Mediterranean",region:"Bosphorus",    terrain:"land",  pop:120000},
  {name:"Naples",         q:  3, r: 16, league:"Mediterranean",region:"Mediterranean",terrain:"coast", pop:286000},
  {name:"Palermo",        q:  2, r: 19, league:"Mediterranean",region:"Mediterranean",terrain:"coast", pop:76153},
  {name:"Tunis",          q:  0, r: 20, league:"Mediterranean",region:"North Africa", terrain:"land",  pop:33194},
  {name:"Alexandria",     q: 14, r: 27, league:"Mediterranean",region:"North Africa", terrain:"land",  pop:227000},
];

const SQ3 = Math.sqrt(3);
const HEX_SIZE = 28;
const W = 680, H = 540;

function hexToPixel(q, r, size) {
  return { x: size * (SQ3 * q + SQ3 / 2 * r), y: size * (1.5 * r) };
}
function hexCorners(cx, cy, size) {
  return Array.from({length:6}, (_,i) => {
    const a = Math.PI / 180 * (60 * i - 30);
    return [cx + size * Math.cos(a), cy + size * Math.sin(a)];
  });
}
function cubeRound(fq, fr) {
  let x = fq, z = fr, y = -x-z;
  let rx=Math.round(x), ry=Math.round(y), rz=Math.round(z);
  const dx=Math.abs(rx-x), dy=Math.abs(ry-y), dz=Math.abs(rz-z);
  if (dx>dy&&dx>dz) rx=-ry-rz; else if (dy>dz) ry=-rx-rz; else rz=-rx-ry;
  return {q:rx, r:rz};
}
function pixelToHex(px, py, size) {
  return cubeRound((SQ3/3*px - 1/3*py)/size, (2/3*py)/size);
}

const CITY_MAP = new Map(CITIES.map(c => [`${c.q},${c.r}`, c]));

const TERRAIN_FILL = { coast:"#122840", land:"#1a2e14", sea:"#07131f" };
const HANSE  = "#d4a547";
const MED    = "#c04428";
const GRID_CITY = "#1a3858";
const GRID_SEA  = "#0c1e30";

function popR(pop) {
  if (pop>200000) return 8;
  if (pop>80000)  return 6;
  if (pop>30000)  return 5;
  if (pop>10000)  return 4;
  return 3;
}

export default function HexMap() {
  const canvasRef = useRef(null);
  const vpRef = useRef({x: W*0.52, y: H*0.32, scale:1});
  const [vp, setVp] = useState(vpRef.current);
  const [selected, setSelected] = useState(null);
  const [filter, setFilter] = useState("all");
  const dragging = useRef(false);
  const last = useRef({x:0,y:0});

  useEffect(() => { vpRef.current = vp; }, [vp]);

  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    const {x:ox, y:oy, scale} = vpRef.current;
    const hs = HEX_SIZE * scale;

    ctx.clearRect(0,0,W,H);
    ctx.fillStyle = "#060f1c";
    ctx.fillRect(0,0,W,H);

    const toW = (px,py) => ({wx:(px-ox)/scale, wy:(py-oy)/scale});
    const corners = [[0,0],[W,0],[0,H],[W,H]].map(([p,q])=>toW(p,q));
    let minQ=Infinity,maxQ=-Infinity,minR=Infinity,maxR=-Infinity;
    for (const {wx,wy} of corners) {
      const h=pixelToHex(wx,wy,HEX_SIZE);
      minQ=Math.min(minQ,h.q-2); maxQ=Math.max(maxQ,h.q+2);
      minR=Math.min(minR,h.r-2); maxR=Math.max(maxR,h.r+2);
    }
    minQ=Math.max(minQ,-22); maxQ=Math.min(maxQ,22);
    minR=Math.max(minR,-12); maxR=Math.min(maxR,32);

    for (let r=minR;r<=maxR;r++) for (let q=minQ;q<=maxQ;q++) {
      const {x:px,y:py} = hexToPixel(q,r,HEX_SIZE);
      const cx = px*scale+ox, cy = py*scale+oy;
      const city = CITY_MAP.get(`${q},${r}`);
      const terrain = city ? city.terrain : "sea";
      const pts = hexCorners(cx,cy,hs*0.96);
      ctx.beginPath();
      ctx.moveTo(pts[0][0],pts[0][1]);
      for (let i=1;i<6;i++) ctx.lineTo(pts[i][0],pts[i][1]);
      ctx.closePath();
      ctx.fillStyle = TERRAIN_FILL[terrain] || TERRAIN_FILL.sea;
      ctx.fill();
      ctx.strokeStyle = city ? GRID_CITY : GRID_SEA;
      ctx.lineWidth = 0.6;
      ctx.stroke();
      if (scale>2.2 && !city) {
        ctx.font = `${Math.max(7,7*scale)}px monospace`;
        ctx.fillStyle = "#162840";
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText(`${q},${r}`,cx,cy);
      }
    }

    const dim = filter !== "all"
      ? new Set(CITIES.filter(c => c.league!==filter && c.region!==filter).map(c=>c.name))
      : new Set();

    for (const city of CITIES) {
      const {x:px,y:py} = hexToPixel(city.q,city.r,HEX_SIZE);
      const cx=px*scale+ox, cy=py*scale+oy;
      if (cx<-40||cx>W+40||cy<-40||cy>H+40) continue;
      const color = city.league==="Hanseatic" ? HANSE : MED;
      const dotR = popR(city.pop)*scale;
      const isSel = selected?.name===city.name;
      ctx.globalAlpha = dim.has(city.name) ? 0.18 : 1;
      ctx.beginPath();
      ctx.arc(cx,cy,dotR,0,Math.PI*2);
      ctx.fillStyle = color;
      ctx.fill();
      if (isSel) {
        ctx.beginPath();
        ctx.arc(cx,cy,dotR+3*scale,0,Math.PI*2);
        ctx.strokeStyle="#ffffff";
        ctx.lineWidth=1.5;
        ctx.stroke();
      }
      if (scale>0.5) {
        const fs = Math.max(9,Math.min(12,10*scale));
        ctx.font=`${fs}px sans-serif`;
        ctx.fillStyle = city.league==="Hanseatic" ? "#dbb455" : "#d86040";
        ctx.textAlign="center";
        ctx.textBaseline="bottom";
        ctx.fillText(city.name,cx,cy-dotR-2*scale);
      }
      ctx.globalAlpha=1;
    }
  }, [selected, filter]);

  useEffect(()=>{ draw(); },[draw,vp]);

  const onDown = e => { dragging.current=true; last.current={x:e.clientX,y:e.clientY}; };
  const onMove = e => {
    if (!dragging.current) return;
    const dx=e.clientX-last.current.x, dy=e.clientY-last.current.y;
    last.current={x:e.clientX,y:e.clientY};
    setVp(v=>{ const n={...v,x:v.x+dx,y:v.y+dy}; vpRef.current=n; return n; });
  };
  const onUp = ()=>{ dragging.current=false; };
  const onWheel = e => {
    e.preventDefault();
    const rect=canvasRef.current.getBoundingClientRect();
    const mx=e.clientX-rect.left, my=e.clientY-rect.top;
    const f=e.deltaY<0?1.12:0.89;
    setVp(v=>{
      const ns=Math.max(0.25,Math.min(5,v.scale*f));
      const rat=ns/v.scale;
      const n={scale:ns,x:mx+(v.x-mx)*rat,y:my+(v.y-my)*rat};
      vpRef.current=n; return n;
    });
  };
  const onClick = e => {
    const rect=canvasRef.current.getBoundingClientRect();
    const {x:ox,y:oy,scale}=vpRef.current;
    const wx=(e.clientX-rect.left-ox)/scale, wy=(e.clientY-rect.top-oy)/scale;
    const {q,r}=pixelToHex(wx,wy,HEX_SIZE);
    setSelected(CITY_MAP.get(`${q},${r}`)||null);
  };
  const zoom = f => setVp(v=>{
    const cx=W/2,cy=H/2,ns=Math.max(0.25,Math.min(5,v.scale*f)),rat=ns/v.scale;
    const n={scale:ns,x:cx+(v.x-cx)*rat,y:cy+(v.y-cy)*rat};
    vpRef.current=n; return n;
  });
  const reset = () => {
    const {x:lx,y:ly}=hexToPixel(0,0,HEX_SIZE);
    const n={x:W*0.52-lx,y:H*0.32-ly,scale:1};
    vpRef.current=n; setVp(n);
  };

  const regions=[...new Set(CITIES.map(c=>c.region))].sort();

  const btnStyle = (active) => ({
    fontSize:12, padding:"4px 10px", cursor:"pointer",
    background: active?"var(--color-background-secondary)":"transparent",
    border: active?"0.5px solid var(--color-border-primary)":"0.5px solid var(--color-border-tertiary)",
    borderRadius:"var(--border-radius-md)",
    color: active?"var(--color-text-primary)":"var(--color-text-secondary)",
  });

  return (
    <div style={{fontFamily:"var(--font-sans)",color:"var(--color-text-primary)"}}>
      <h2 className="sr-only">Patrician III/IV hex map — 34 cities on a pointy-top axial grid, Lübeck at (0,0), 1 hex ≈ 50 nm.</h2>

      <div style={{display:"flex",gap:8,marginBottom:8,flexWrap:"wrap",alignItems:"center"}}>
        {[{l:"All",v:"all"},{l:"Hanseatic",v:"Hanseatic"},{l:"Mediterranean",v:"Mediterranean"}].map(f=>(
          <button key={f.v} onClick={()=>setFilter(f.v)} style={btnStyle(filter===f.v)}>{f.l}</button>
        ))}
        <select
          value={regions.includes(filter)?filter:""}
          onChange={e=>setFilter(e.target.value||"all")}
          style={{fontSize:12,height:28,borderRadius:"var(--border-radius-md)",border:"0.5px solid var(--color-border-tertiary)",background:"var(--color-background-primary)",color:"var(--color-text-secondary)",paddingLeft:6}}
        >
          <option value="">Region…</option>
          {regions.map(r=><option key={r} value={r}>{r}</option>)}
        </select>
        <button onClick={reset} style={{...btnStyle(false),marginLeft:"auto"}}>reset view</button>
      </div>

      <div style={{position:"relative",borderRadius:"var(--border-radius-lg)",overflow:"hidden",border:"0.5px solid var(--color-border-tertiary)"}}>
        <canvas
          ref={canvasRef} width={W} height={H}
          onMouseDown={onDown} onMouseMove={onMove} onMouseUp={onUp} onMouseLeave={onUp}
          onWheel={onWheel} onClick={onClick}
          style={{display:"block",cursor:"crosshair",maxWidth:"100%"}}
        />

        {/* Legend */}
        <div style={{position:"absolute",top:10,left:10,background:"rgba(5,12,22,0.9)",padding:"10px 12px",borderRadius:"var(--border-radius-md)",border:"0.5px solid #152030"}}>
          <div style={{fontSize:10,color:"#3a5868",marginBottom:5,letterSpacing:"0.07em",textTransform:"uppercase"}}>League</div>
          {[[HANSE,"Hanseatic"],[MED,"Mediterranean"]].map(([c,l])=>(
            <div key={l} style={{display:"flex",alignItems:"center",gap:6,marginBottom:3}}>
              <div style={{width:7,height:7,borderRadius:"50%",background:c}}/>
              <span style={{fontSize:11,color:c}}>{l}</span>
            </div>
          ))}
          <div style={{borderTop:"0.5px solid #152030",marginTop:7,paddingTop:7}}>
            <div style={{fontSize:10,color:"#3a5868",marginBottom:4,letterSpacing:"0.07em",textTransform:"uppercase"}}>Terrain</div>
            {[["coast","#122840"],["land","#1a2e14"],["sea","#07131f"]].map(([t,c])=>(
              <div key={t} style={{display:"flex",alignItems:"center",gap:6,marginBottom:2}}>
                <div style={{width:13,height:8,borderRadius:2,background:c,border:"0.5px solid #1a3050"}}/>
                <span style={{fontSize:10,color:"#5a7888"}}>{t}</span>
              </div>
            ))}
          </div>
          <div style={{borderTop:"0.5px solid #152030",marginTop:7,paddingTop:7}}>
            <div style={{fontSize:10,color:"#3a5868",marginBottom:4,letterSpacing:"0.07em",textTransform:"uppercase"}}>Dot = population</div>
            {[[3,"&lt; 10k"],[5,"30k"],[7,"80k"],[8,"200k+"]].map(([r,l])=>(
              <div key={l} style={{display:"flex",alignItems:"center",gap:7,marginBottom:2}}>
                <div style={{width:r*2,height:r*2,borderRadius:"50%",background:"#4a6880",flexShrink:0}}/>
                <span style={{fontSize:10,color:"#5a7888"}} dangerouslySetInnerHTML={{__html:l}}/>
              </div>
            ))}
          </div>
        </div>

        {/* City info panel */}
        {selected && (
          <div style={{position:"absolute",top:10,right:10,background:"rgba(5,12,22,0.93)",padding:"12px 14px",borderRadius:"var(--border-radius-md)",border:`0.5px solid ${selected.league==="Hanseatic"?HANSE:MED}`,minWidth:175}}>
            <div style={{fontSize:14,fontWeight:500,color:selected.league==="Hanseatic"?HANSE:MED,marginBottom:9}}>{selected.name}</div>
            <table style={{fontSize:12,borderCollapse:"collapse",width:"100%"}}>
              <tbody>
                {[
                  ["League",  selected.league],
                  ["Region",  selected.region],
                  ["Terrain", selected.terrain],
                  ["Hex (q, r)", `(${selected.q}, ${selected.r})`],
                  ["s =",     `${-selected.q-selected.r}`],
                  ["Population", selected.pop.toLocaleString()],
                ].map(([k,v])=>(
                  <tr key={k}>
                    <td style={{color:"#3a6070",paddingRight:10,paddingBottom:3,fontSize:11,whiteSpace:"nowrap"}}>{k}</td>
                    <td style={{color:"#b0ccd8",fontFamily:k.includes("Hex")||k==="s ="?"var(--font-mono)":"inherit"}}>{v}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <button onClick={()=>setSelected(null)} style={{marginTop:10,fontSize:10,color:"#2a4050",background:"none",border:"none",cursor:"pointer",padding:0}}>dismiss ×</button>
          </div>
        )}

        {/* Zoom buttons */}
        <div style={{position:"absolute",bottom:10,right:10,display:"flex",flexDirection:"column",gap:4}}>
          {[["+",1.25],["−",0.8]].map(([l,f])=>(
            <button key={l} onClick={()=>zoom(f)} style={{width:30,height:30,background:"rgba(5,12,22,0.88)",border:"0.5px solid #152030",color:"#5a8090",borderRadius:4,cursor:"pointer",fontSize:18,lineHeight:1}}>{l}</button>
          ))}
        </div>

        <div style={{position:"absolute",bottom:10,left:10,fontSize:10,color:"#182838"}}>
          scroll to zoom · drag to pan · click city to inspect · 1 hex ≈ 50 nm
        </div>
      </div>

      <div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(130px,1fr))",gap:10,marginTop:10}}>
        {[
          {label:"Cities",    value:CITIES.length},
          {label:"Hanseatic", value:CITIES.filter(c=>c.league==="Hanseatic").length},
          {label:"Mediterranean",value:CITIES.filter(c=>c.league==="Mediterranean").length},
          {label:"Scale",     value:"1 hex ≈ 50 nm"},
        ].map(s=>(
          <div key={s.label} style={{background:"var(--color-background-secondary)",padding:"10px 14px",borderRadius:"var(--border-radius-md)"}}>
            <div style={{fontSize:11,color:"var(--color-text-secondary)",marginBottom:3}}>{s.label}</div>
            <div style={{fontSize:18,fontWeight:500}}>{s.value}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

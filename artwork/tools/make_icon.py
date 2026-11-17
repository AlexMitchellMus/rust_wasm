"""rustc.wasm icon: a sphere with two swirl tails (exact log-spiral geometry) that release droplets of data."""
import math,os,sys
cx=cy=256
R=86
CO=0.085       # outer edge: r = R(1 + CO*th^2), leaves the sphere exactly tangentially
CI=0.42        # inner edge: r = R(1 + CI*(th-TD)^2), also tangential, closes onto the outer edge
TD=0.50*math.pi  # where the inner edge leaves the sphere (angle after the outer edge)
A0=math.radians(-135)
BITS=["1101101","1011011"]
def lerp(c0,c1,t):
    a=[int(c0[i:i+2],16) for i in (1,3,5)]; b=[int(c1[i:i+2],16) for i in (1,3,5)]
    return "#"+"".join(f"{round(a[k]+(b[k]-a[k])*t):02x}" for k in range(3))
def ramp(t):
    return lerp("#c04dff","#ff4f8a",t/0.45) if t<0.45 else lerp("#ff4f8a","#ff9a2e",(t-0.45)/0.55)
TEND=math.sqrt(CI)*TD/(math.sqrt(CI)-math.sqrt(CO))   # outer and inner edges meet here
def RO(th): return R*(1+CO*th*th)
def RI(th): return R*(1+CI*(th-TD)**2)
def P(a,r): return (cx+r*math.cos(a), cy+r*math.sin(a))
def outline():
    pts=[]
    N=220
    for arm in range(2):
        a0=A0+math.pi*arm
        for i in range(N+1):             # outer edge: sphere -> tip
            th=TEND*i/N; pts.append(P(a0+th, RO(th)))
        for i in range(N,-1,-1):         # inner edge: tip -> back onto the sphere
            th=TD+(TEND-TD)*i/N; pts.append(P(a0+th, RI(th)))
        for i in range(1,N):             # sphere arc to the next tail
            th=TD+(math.pi-TD)*i/N; pts.append(P(a0+th, R))
    return "M"+" L".join(f"{x:.2f},{y:.2f}" for x,y in pts)+" Z"
def droplets():
    out=[]
    for arm in range(2):
        a0=A0+math.pi*arm
        th=TEND; size=8.6
        r=RO(th); th+= (size+6)/r
        for k,b in enumerate(BITS[arm]):
            r=RO(th)*(1+0.012*(th-TEND))
            x,y=P(a0+th,r); out.append((x,y,size,k,b))
            nxt=max(3.6,size*0.84); th+=(size+nxt)*1.65/r; size=nxt
    return out
D=droplets(); PATH=outline(); n=len(BITS[0])
def colour():
    dots="".join(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{s:.2f}" fill="{ramp(k/(n-1))}"'+('' if b=="1" else ' fill-opacity="0.3"')+'/>' for x,y,s,k,b in D)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <title>rustc.wasm</title>
  <defs>
    <radialGradient id="core" gradientUnits="userSpaceOnUse" cx="{cx-R*0.35:.1f}" cy="{cy-R*0.4:.1f}" r="{R*2.6:.1f}">
      <stop offset="0" stop-color="#c3b0ff"/><stop offset="0.3" stop-color="#7a52f5"/><stop offset="1" stop-color="#2f178f"/>
    </radialGradient>
  </defs>
  {dots}
  <path d="{PATH}" fill="url(#core)"/>
</svg>
'''
def mono(ink):
    dots="".join(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{s:.2f}"'+('' if b=="1" else ' fill-opacity="0.25"')+'/>' for x,y,s,k,b in D)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <title>rustc.wasm</title>
  <g fill="{ink}">
  {dots}
  <path d="{PATH}"/>
  </g>
</svg>
'''
out=sys.argv[1] if len(sys.argv)>1 else os.path.join(os.path.dirname(os.path.abspath(__file__)),"..")
open(f"{out}/icon.svg","w").write(colour())
open(f"{out}/icon-silhouette-white.svg","w").write(mono("#ffffff"))
open(f"{out}/icon-silhouette-black.svg","w").write(mono("#000000"))
print("tip radius",round(RO(TEND)),"max width",round(max(RO(t)-RI(t) for t in [TD+i*(TEND-TD)/200 for i in range(201)])),
      "edge",round(min(min(x-s,y-s,512-x-s,512-y-s) for x,y,s,k,b in D)))

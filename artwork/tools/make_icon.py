"""Generate the rustc.wasm icon: a sphere throwing off two spiral data tails.

Usage: python3 make_icon.py [OUTPUT_DIR]   (default: the artwork/ folder)
Writes icon.svg, icon-silhouette-white.svg and icon-silhouette-black.svg.
"""
import math,os,sys
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from blob import field_contour, smooth_path
cx=cy=256
R=82
B=0.30                      # spiral pitch: r = r0 * exp(B*theta)
R0=R*0.80
TAIL=0.92*math.pi           # angular length of the fused tail
W0,W1=R*0.52,13.5            # tail width (radius) at the sphere and at its tip
def lerp(c0,c1,t):
    a=[int(c0[i:i+2],16) for i in (1,3,5)]; b=[int(c1[i:i+2],16) for i in (1,3,5)]
    return "#"+"".join(f"{round(a[k]+(b[k]-a[k])*t):02x}" for k in range(3))
def ramp(t):
    return lerp("#c04dff","#ff4f8a",t/0.45) if t<0.45 else lerp("#ff4f8a","#ff9a2e",(t-0.45)/0.55)
def sp(a0,th):
    r=R0*math.exp(B*th); return cx+r*math.cos(a0+th), cy+r*math.sin(a0+th)
def smoothstep(t): return t*t*(3-2*t)
BITS=["110110111","101101101"]
T=2.0
chain=[(cx,cy,R*T**(1/8))]
drops=[]
for arm in range(2):
    a0=-math.pi*0.75+math.pi*arm       # tails leave the sphere heading round at 45 degrees
    th=0.0
    while th<=TAIL:
        u=th/TAIL; w=W0+(W1-W0)*smoothstep(u)
        x,y=sp(a0,th); chain.append((x,y,w))
        r=R0*math.exp(B*th); th+=0.45*w/r
    # droplets continue along the same spiral, shrinking and spreading
    size=W1*0.98; gap=size*2.2
    x,y=sp(a0,th); th_r=R0*math.exp(B*th); th+= (W1+size+6)/th_r
    for k,b in enumerate(BITS[arm]):
        x,y=sp(a0,th)
        drops.append((x,y,size,k,b,arm))
        nxt=max(5.5,size*0.86)
        r=R0*math.exp(B*th); th+=(size+nxt)*1.32/r
        size=nxt
_pts=field_contour(chain,threshold=T,step=1.0,power=8)
_xs=[x for x,y in _pts]+[x-sz for x,y,sz,k,b,a in drops]+[x+sz for x,y,sz,k,b,a in drops]
_ys=[y for x,y in _pts]+[y-sz for x,y,sz,k,b,a in drops]+[y+sz for x,y,sz,k,b,a in drops]
DX=256-(min(_xs)+max(_xs))/2; DY=256-(min(_ys)+max(_ys))/2
_pts=[(x+DX,y+DY) for x,y in _pts]
drops=[(x+DX,y+DY,sz,k,b,a) for x,y,sz,k,b,a in drops]
cx+=DX; cy+=DY
BLOB=smooth_path(_pts,every=2)
print("shift",round(DX,1),round(DY,1))
n=len(BITS[0])
def colour():
    dots="".join(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{s:.2f}" fill="{ramp(k/(n-1))}"'+('' if b=="1" else ' fill-opacity="0.3"')+'/>' for x,y,s,k,b,a in drops)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <title>rustc.wasm</title>
  <defs>
    <radialGradient id="core" gradientUnits="userSpaceOnUse" cx="{cx-R*0.35:.1f}" cy="{cy-R*0.4:.1f}" r="{R*2.4:.1f}">
      <stop offset="0" stop-color="#c3b0ff"/><stop offset="0.35" stop-color="#7a52f5"/><stop offset="1" stop-color="#2f178f"/>
    </radialGradient>
  </defs>
  {dots}
  <path d="{BLOB}" fill="url(#core)"/>
</svg>
'''
def mono(ink):
    dots="".join(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{s:.2f}"'+('' if b=="1" else ' fill-opacity="0.25"')+'/>' for x,y,s,k,b,a in drops)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <title>rustc.wasm</title>
  <g fill="{ink}">
  {dots}
  <path d="{BLOB}"/>
  </g>
</svg>
'''
out=sys.argv[1] if len(sys.argv)>1 else os.path.join(os.path.dirname(os.path.abspath(__file__)),'..')
open(f"{out}/icon.svg","w").write(colour())
open(f"{out}/icon-silhouette-white.svg","w").write(mono("#ffffff"))
open(f"{out}/icon-silhouette-black.svg","w").write(mono("#000000"))
print("edge",round(min(min(x-s,y-s,512-x-s,512-y-s) for x,y,s,k,b,a in drops),1))

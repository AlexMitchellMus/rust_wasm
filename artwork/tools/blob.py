import math
def field_contour(balls, threshold=1.0, step=1.0, bbox=None, power=2):
    """Trace the f=threshold contour of f(p)=sum (r/d)^2 with marching squares; returns a closed point list."""
    xs=[b[0] for b in balls]; ys=[b[1] for b in balls]; rs=[b[2] for b in balls]
    x0=min(x-r for x,r in zip(xs,rs))-40; x1=max(x+r for x,r in zip(xs,rs))+40
    y0=min(y-r for y,r in zip(ys,rs))-40; y1=max(y+r for y,r in zip(ys,rs))+40
    nx=int((x1-x0)/step)+1; ny=int((y1-y0)/step)+1
    def f(x,y):
        s=0.0
        for bx,by,br in balls:
            d2=(x-bx)**2+(y-by)**2+1e-9; s+=(br*br/d2)**(power/2)
        return s-threshold
    g=[[f(x0+i*step,y0+j*step) for i in range(nx)] for j in range(ny)]
    segs={}
    def interp(i1,j1,i2,j2):
        v1=g[j1][i1]; v2=g[j2][i2]; t=v1/(v1-v2)
        return (round(x0+(i1+(i2-i1)*t)*step,3), round(y0+(j1+(j2-j1)*t)*step,3))
    edges=[]
    for j in range(ny-1):
        for i in range(nx-1):
            c=[(i,j),(i+1,j),(i+1,j+1),(i,j+1)]
            v=[g[b][a] for a,b in c]
            pts=[]
            for k in range(4):
                a=c[k]; b=c[(k+1)%4]
                va=g[a[1]][a[0]]; vb=g[b[1]][b[0]]
                if (va>0)!=(vb>0): pts.append(interp(a[0],a[1],b[0],b[1]))
            if len(pts)==2: edges.append((pts[0],pts[1]))
            elif len(pts)==4: edges.append((pts[0],pts[1])); edges.append((pts[2],pts[3]))
    adj={}
    for a,b in edges:
        adj.setdefault(a,[]).append(b); adj.setdefault(b,[]).append(a)
    # walk the longest loop
    seen=set(); loops=[]
    for start in adj:
        if start in seen: continue
        loop=[start]; seen.add(start); prev=None; cur=start
        while True:
            nxt=[p for p in adj[cur] if p!=prev and p not in seen]
            if not nxt: break
            prev,cur=cur,nxt[0]; seen.add(cur); loop.append(cur)
        loops.append(loop)
    return max(loops,key=len)
def smooth_path(pts, every=3):
    pts=pts[::every]
    n=len(pts)
    # Catmull-Rom to cubic Bezier, closed
    out=f"M{pts[0][0]:.2f},{pts[0][1]:.2f}"
    for i in range(n):
        p0=pts[(i-1)%n]; p1=pts[i]; p2=pts[(i+1)%n]; p3=pts[(i+2)%n]
        c1=(p1[0]+(p2[0]-p0[0])/6, p1[1]+(p2[1]-p0[1])/6)
        c2=(p2[0]-(p3[0]-p1[0])/6, p2[1]-(p3[1]-p1[1])/6)
        out+=f" C{c1[0]:.2f},{c1[1]:.2f} {c2[0]:.2f},{c2[1]:.2f} {p2[0]:.2f},{p2[1]:.2f}"
    return out+" Z"

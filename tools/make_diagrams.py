"""Generate portable, self-contained SVG architecture diagrams for GitHub README.

The diagrams are documentation only and deliberately include no scripting,
external image resources or interactive elements.
"""
from pathlib import Path
from xml.sax.saxutils import escape

BASE = Path(__file__).resolve().parents[1] / 'docs' / 'diagrams'
BASE.mkdir(parents=True, exist_ok=True)

BG = '#0b1220'
PANEL = '#111e30'
MUTED = '#96aabe'
WHITE = '#e9f1fa'
TEAL = '#2dd4bf'
BLUE = '#74a9ff'
VIOLET = '#c4a1ff'
ORANGE = '#ffcc78'


def svg_start(width, height, name):
    return [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-label="{escape(name)}">',
            f'<title>{escape(name)}</title>',
            f'<rect width="{width}" height="{height}" fill="{BG}"/>',
            '<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="#8297af"/></marker></defs>']

def text(parts, x, y, val, size=20, color=WHITE, anchor='middle', bold=False):
    parts.append(f'<text x="{x}" y="{y}" font-family="Segoe UI, Arial, sans-serif" font-size="{size}" font-weight="{650 if bold else 400}" fill="{color}" text-anchor="{anchor}">{escape(val)}</text>')

def box(parts, x, y, w, h, title, detail='', color=TEAL, radius=14, title_size=19):
    parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{PANEL}" stroke="{color}" stroke-opacity=".85" stroke-width="2"/>')
    mid=y+h/2
    text(parts,x+w/2,mid-(6 if detail else -7),title,title_size,WHITE,bold=True)
    if detail: text(parts,x+w/2,mid+19,detail,14,MUTED)

def arrow(parts,x1,y1,x2,y2,color='#8297af',dash=False):
    dashattr=' stroke-dasharray="7 7"' if dash else ''
    parts.append(f'<path d="M{x1} {y1} L{x2} {y2}" stroke="{color}" stroke-width="2.5" fill="none" marker-end="url(#arrow)"{dashattr}/>')

def path(parts,d,color='#8297af',dash=False):
    dashattr=' stroke-dasharray="7 7"' if dash else ''
    parts.append(f'<path d="{d}" stroke="{color}" stroke-width="2.5" fill="none" marker-end="url(#arrow)"{dashattr}/>')

def save(name,parts):
    target=BASE/name
    target.write_text('\n'.join(parts+['</svg>','']),encoding='utf-8')
    return target

p=svg_start(1200,770,'XDF-1 sensory event computing architecture')
text(p,600,45,'XDF-1  /  SENSORY INTELLIGENCE ARCHITECTURE',27,WHITE,bold=True)
text(p,600,75,'Many asynchronous sources  •  Concurrent processing  •  Continuous feedback',17,MUTED)
for x,label,sub in [(60,'MOTION','IMU / encoders'),(330,'VISION','Camera events'),(600,'DISTANCE','Radar / LiDAR'),(870,'OTHER','Environmental / RF')]:
    box(p,x,111,260,78,label,sub,BLUE)
    arrow(p,x+130,189,x+130,222)
box(p,90,223,1020,96,'SENSORY EVENT FABRIC  (SEF)','Identify • Timestamp • Validate • Queue • Prioritize • Regulate ingress',TEAL,title_size=24)
arrow(p,600,319,600,351)
p.append('<rect x="90" y="353" width="1020" height="114" rx="14" fill="%s" stroke="%s" stroke-opacity=".85" stroke-width="2"/>' % (PANEL, BLUE))
text(p,600,386,'CONFIGURABLE DATAFLOW EXECUTION FABRIC',22,WHITE,bold=True)
text(p,600,406,'Independent token-ready operations and bounded backpressure',14,MUTED)
for x,i in [(139,0),(393,1),(647,2),(901,3)]:
    p.append(f'<rect x="{x}" y="421" width="160" height="35" rx="7" fill="#183457" stroke="{BLUE}" stroke-opacity=".8"/>')
    text(p,x+80,444,f'TILE {i}',16,WHITE,bold=True)
arrow(p,600,467,600,498)
box(p,90,500,1020,81,'STATE + SENSOR FUSION','Temporal correlation • Filtering • Windowed summaries • Confidence',VIOLET,title_size=22)
arrow(p,600,581,600,610)
box(p,90,611,1020,73,'DECISION ENGINE','Fast reflex path  +  Contextual decisions  +  Observable explanations',ORANGE,title_size=21)
arrow(p,600,684,600,705)
box(p,375,707,450,49,'ACTIONS / TELEMETRY / FEEDBACK',color=TEAL,title_size=17)
path(p,'M375 731 H37 V271 H89',TEAL,True)
text(p,43,695,'feedback',13,TEAL,anchor='start')
save('sensory-fabric.svg',p)

p=svg_start(1200,550,'XDF-1 fast reflex and contextual decision processing paths')
text(p,600,47,'TWO COMPLEMENTARY RESPONSE PATHS',27,WHITE,bold=True)
text(p,600,79,'The architecture must not make urgent events wait for unrelated analysis.',17,MUTED)
for x,accent,heading,subtitle,boxes in [
    (55,ORANGE,'FAST REFLEX PATH','Latency-sensitive, bounded computation',
     [('URGENT EVENT','Threshold / hardware flag'),('DIRECT DATAFLOW RULE','Simple deterministic operation'),('IMMEDIATE OUTPUT','Actuate / flag / alert')]),
    (645,VIOLET,'CONTEXTUAL DECISION PATH','Correlated, stateful observations',
     [('MULTIPLE SENSOR EVENTS','Independent streams + timestamps'),('STATE + FUSION','Temporal alignment / confidence'),('DECISION + SUMMARY','Rule / model / explanation')])
]:
    p.append(f'<rect x="{x}" y="113" width="500" height="405" rx="18" fill="#101d2e" stroke="{accent}" stroke-width="2"/>')
    text(p,x+250,151,heading,22,accent,bold=True)
    text(p,x+250,177,subtitle,15,MUTED)
    ys=[210,315,420]
    for i,(name,desc) in enumerate(boxes):
        box(p,x+43,ys[i],414,75,name,desc,accent,title_size=19)
        if i<2: arrow(p,x+250,ys[i]+75,x+250,ys[i+1]-2)
text(p,600,541,'Both paths require explicit latency budgets, bounded queues, and safe fallback behavior.',14,MUTED)
save('decision-paths.svg',p)

p=svg_start(1200,470,'Conventional instruction sequencing compared with tagged-token dataflow')
text(p,600,45,'WHAT MAKES XDF-1 DIFFERENT?',27,WHITE,bold=True)
text(p,600,75,'Illustrative execution models — modern CPUs also execute operations in parallel.',16,MUTED)
text(p,300,126,'INSTRUCTION-CENTRIC MODEL',21,BLUE,bold=True)
text(p,900,126,'TAGGED-TOKEN DATAFLOW MODEL',21,TEAL,bold=True)
box(p,155,160,290,63,'INSTRUCTION SEQUENCE',color=BLUE,title_size=18)
arrow(p,300,223,300,251)
box(p,155,253,290,63,'FETCH / DECODE / ISSUE',color=BLUE,title_size=18)
arrow(p,300,316,300,344)
box(p,155,346,290,63,'EXECUTE + RETIRE',color=BLUE,title_size=18)
box(p,644,170,160,70,'TOKEN A',color=TEAL,title_size=20)
box(p,996,170,160,70,'TOKEN B',color=TEAL,title_size=20)
path(p,'M724 240 L862 298',TEAL)
path(p,'M1076 240 L938 298',TEAL)
box(p,810,300,180,64,'NODE FIRES','when operands ready',TEAL,title_size=19)
arrow(p,900,364,900,392,TEAL)
box(p,810,396,180,59,'OUTPUT EVENT',color=TEAL,title_size=18)
save('execution-model.svg',p)
print('Created SVGs:')
for f in BASE.glob('*.svg'):print(f.name,f.stat().st_size)

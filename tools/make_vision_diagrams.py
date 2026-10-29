"""Reproducibly generate GitHub-safe, self-contained XDF-1 vision SVGs.

No images, external fonts, links, scripting, or network resources embedded.
"""
from pathlib import Path
from xml.sax.saxutils import escape

BASE = Path(__file__).resolve().parents[1] / 'docs' / 'diagrams'
BASE.mkdir(parents=True, exist_ok=True)
NAVY = '#0a1425'; PANEL = '#10253a'; WHITE = '#edf5ff'; MUTED = '#a7bed1'
CYAN = '#4fe1d2'; BLUE = '#7cb5ff'; GOLD = '#ffd18a'; PINK = '#e8a6f3'


def begin(w,h,title):
    return [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="{escape(title)}">',
            f'<title>{escape(title)}</title>',
            f'<rect width="{w}" height="{h}" fill="{NAVY}"/>',
            '<defs><marker id="arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path d="M0 0 L10 5 L0 10z" fill="#7892aa"/></marker></defs>']


def txt(p,x,y,value,size=18,color=WHITE,anchor='middle',weight=400):
    p.append(f'<text x="{x}" y="{y}" fill="{color}" text-anchor="{anchor}" font-family="Arial, DejaVu Sans, sans-serif" font-size="{size}" font-weight="{weight}">{escape(value)}</text>')


def rect(p,x,y,w,h,title,subtitle='',c=BLUE,ts=19):
    p.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="13" fill="{PANEL}" stroke="{c}" stroke-width="2"/>')
    txt(p,x+w/2,y+32,title,ts,WHITE,weight=700)
    if subtitle: txt(p,x+w/2,y+55,subtitle,13,MUTED)


def arrow(p,x1,y1,x2,y2,dash=False):
    extra=' stroke-dasharray="7 7"' if dash else ''
    p.append(f'<path d="M{x1} {y1} L{x2} {y2}" fill="none" stroke="#7892aa" stroke-width="2.4" marker-end="url(#arr)"{extra}/>')


def line(p,path,c=CYAN,dash=False):
    extra=' stroke-dasharray="7 7"' if dash else ''
    p.append(f'<path d="{path}" fill="none" stroke="{c}" stroke-width="2.2" marker-end="url(#arr)"{extra}/>')


def save(name,p):
    (BASE/name).write_text('\n'.join(p+['</svg>','']),encoding='utf-8')

# Main architectural map: physical raw data remains in DRAM; small events go to XDF.
p=begin(1400,780,'XDF-1 hybrid sensory intelligence: perception, reflexes, working state and memory')
txt(p,700,44,'XDF-1  |  COMPUTING THAT PERCEIVES, DECIDES AND REMEMBERS',27,WHITE,weight=700)
txt(p,700,74,'50+ planned sensor types  /  asynchronous modalities  /  500 MB/s research input target',16,MUTED)
for x,heading,detail in [(60,'KINEMATICS','IMU + position'),(335,'SPACE','LiDAR + radar'),(610,'VISION','Cameras + thermal'),(885,'AUDIO','Microphone + vibration'),(1160,'OTHER','Environment + bio')]:
    rect(p,x,107,220,79,heading,detail,BLUE,18)
    arrow(p,x+110,186,x+110,216)
rect(p,65,220,1270,80,'USAL  /  UNIVERSAL SENSOR ACQUISITION','Protocol adapters + clock correlation + validity / quality + sampling policies',CYAN,23)
line(p,'M700 300 V326 H365 V356',BLUE)
line(p,'M700 326 H1040 V356',BLUE)
rect(p,72,358,586,90,'RAW PAYLOAD DATA PLANE','External DRAM ring  •  DMA  •  camera / LiDAR / audio buffers',BLUE,20)
rect(p,742,358,586,90,'SEF  /  EVENT & FEATURE PLANE','Small timestamped observations  •  priorities  •  backpressure',CYAN,20)
line(p,'M365 448 V480',BLUE)
line(p,'M1035 448 V480',CYAN)
rect(p,72,482,586,94,'NPE  /  NEURAL PERCEPTION','Specialist encoders  •  multimodal fusion  •  uncertainty',PINK,20)
rect(p,742,482,586,94,'XDF  /  FAST REFLEX + DECISION','Tagged dataflow  •  rules  •  predictable control path',GOLD,19)
line(p,'M658 528 H742',PINK)
line(p,'M1035 576 V607 H700 V618',GOLD)
line(p,'M365 576 V607 H700 V618',PINK)
rect(p,317,622,766,92,'WORLD STATE + AMEE  /  SELECTIVE EXPERIENCE MEMORY','Live context in RAM  •  important episodes  •  long-term recall',CYAN,20)
line(p,'M700 714 V737 H1345 V256 H1335',CYAN,True)
txt(p,1060,751,'feedback: attention, recall, adaptive sensing',14,CYAN)
save('xdf-vision.svg',p)

p=begin(1280,620,'XDF-1 data lifetimes: raw, active perception, and episodic memory')
txt(p,640,48,'THREE DATA LIFETIMES  |  EXPERIENCE WITHOUT RECORDING EVERYTHING',26,WHITE,weight=700)
txt(p,640,79,'Continuous sensor input is the present; current state is understanding; selective archive is memory.',15,MUTED)
rect(p,66,125,1148,92,'LIVE ENVIRONMENT  /  500 MB/s','4 Gb/s raw target  •  sensor-specific streams  •  normal observations are temporary',BLUE,23)
arrow(p,640,217,640,254)
rect(p,76,259,520,101,'TRANSIENT RAW MEMORY','5-30 s external DRAM ring  •  2.5-15 GB at target rate',BLUE,20)
rect(p,684,259,520,101,'ACTIVE PERCEPTION','Features + fused world state + attention + reflex',PINK,20)
line(p,'M596 310 H684',CYAN)
line(p,'M336 360 V394 H640 V412',BLUE)
line(p,'M944 360 V394 H640 V412',PINK)
rect(p,322,413,636,86,'AMEE  /  IMPORTANCE + CONTEXT SELECTOR','Novelty  •  safety  •  relevance  •  uncertainty  •  past experience',CYAN,21)
line(p,'M640 499 V522',CYAN)
rect(p,176,526,928,74,'PERSISTENT EPISODES  /  AVERAGE TARGET: 1-10%','5-50 MB/s  •  432 GB-4.32 TB/day  •  exceptions for protected events',GOLD,21)
txt(p,1200,615,'1-10% is an objective, never a hard limit on critical evidence.',14,MUTED,anchor='end')
save('perception-memory.svg',p)

p=begin(1280,426,'XDF-1 engineering milestones and independently verified scope')
txt(p,640,46,'ENGINEERING ROADMAP  |  OBSERVE REAL PROGRESS',27,WHITE,weight=700)
txt(p,640,78,'Verified hardware is separate from reference software and planned physical capabilities.',16,MUTED)
for x,title,status,desc,desc2,c in [
(46,'M2.1','RTL VERIFIED','64 streams + 4 lanes','XDF arithmetic bridge',CYAN),
(357,'M2.2A','REFERENCE MODEL','Data lifetimes + AMEE','Retention + documentation',BLUE),
(668,'M2.2B','TO IMPLEMENT','Programmable reflex','Neural adapter + state',PINK),
(979,'M3+','FUTURE HARDWARE','DMA + high-speed I/O','FPGA + measured watts',GOLD)]:
    p.append(f'<rect x="{x}" y="126" width="255" height="213" rx="16" fill="{PANEL}" stroke="{c}" stroke-width="2"/>')
    txt(p,x+127,168,title,25,WHITE,weight=700)
    txt(p,x+127,205,status,15,c,weight=700)
    txt(p,x+127,247,desc,15,WHITE)
    txt(p,x+127,272,desc2,15,MUTED)
    if x<979: arrow(p,x+257,223,x+308,223)
txt(p,640,386,'No current evidence of physical 500 MB/s handling, neural acceleration, FPGA Fmax or sensor-to-action power.',15,MUTED)
save('milestones.svg',p)
print('\n'.join(f'{p.name}: {p.stat().st_size} bytes' for p in BASE.glob('*.svg')))

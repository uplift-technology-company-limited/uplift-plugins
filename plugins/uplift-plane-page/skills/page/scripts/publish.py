#!/usr/bin/env python3
"""สร้าง / อัปเดต / ดูรายการ Plane page ผ่าน Django shell ในคอนเทนเนอร์ plane-api

Plane public API สร้างหรือแก้ page ไม่ได้ จึงเขียนเข้า model ตรง ๆ
  create : publish.py page.md --project <project> --name "ชื่อ page"
  update : publish.py page.md --page-id <uuid>
  list   : publish.py --list --project <project>
"""
import argparse, glob, json, os, re, subprocess, sys, tempfile

CONTAINER = os.environ.get("PLANE_API_CONTAINER", "uplift-dev-plane-api-1")


def find_markdown_it():
    hits = sorted(glob.glob(os.path.expanduser("~/dev/*/node_modules/markdown-it/index.mjs")))
    if not hits:
        sys.exit("ไม่พบ markdown-it ใน ~/dev/*/node_modules — ติดตั้งในรีโปใดก็ได้ (bun add markdown-it)")
    return hits[0]


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")


def prepare_images(src, base_dir, workdir):
    """แปลงบล็อก mermaid เป็น PNG แล้วคืน (markdown ใหม่, รายการรูป local ที่ต้องอัปโหลด)"""
    render = os.path.join(os.path.dirname(__file__), "render_mermaid.mjs")
    n = 0

    def mermaid_to_img(m):
        nonlocal n
        n += 1
        mmd, png = os.path.join(workdir, f"diagram{n}.mmd"), os.path.join(workdir, f"diagram{n}.png")
        open(mmd, "w", encoding="utf-8").write(m.group(1))
        subprocess.run(["bun", "run", render, mmd, png], check=True, capture_output=True)
        return f"![แผนภาพ {n}]({png})"

    src = re.sub(r"```mermaid\n(.*?)```", mermaid_to_img, src, flags=re.S)
    images = []
    for m in re.finditer(r"!\[[^\]]*\]\(([^)\s]+)\)", src):
        ref = m.group(1)
        if ref.startswith(("http://", "https://")):
            continue
        path = ref if os.path.isabs(ref) else os.path.join(base_dir, ref)
        if not os.path.exists(path):
            sys.exit(f"ไม่พบรูป {ref}")
        w, h = png_size(path) if path.lower().endswith(".png") else (800, 600)
        images.append({"ref": ref, "path": path, "name": os.path.basename(path), "w": w, "h": h})
    return src, images


def md_to_html(src):
    js = (
        f'import MarkdownIt from "{find_markdown_it()}";'
        'const md=new MarkdownIt({html:false,linkify:true});'
        'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(md.render(s)));'
    )
    with tempfile.NamedTemporaryFile("w", suffix=".mjs", delete=False) as f:
        f.write(js)  # noqa
    try:
        return subprocess.run(["bun", "run", f.name], input=src, capture_output=True, text=True, check=True).stdout
    finally:
        os.unlink(f.name)


def django(code, env):
    args = ["docker", "exec"]
    for k, v in env.items():
        args += ["-e", f"{k}={v}"]
    args += [CONTAINER, "python", "manage.py", "shell", "-c", code]
    out = subprocess.run(args, capture_output=True, text=True)
    lines = [l for l in (out.stdout + out.stderr).splitlines() if "objects imported" not in l and l.strip()]
    print("\n".join(lines))
    if out.returncode:
        sys.exit(out.returncode)


PRELUDE = """
import os, re, json, uuid
from plane.db.models import Page, ProjectPage, Project, FileAsset
from plane.settings.storage import S3Storage
def strip(h): return re.sub('<[^>]+>', '', h)[:5000]
def attach_images(p, proj, html):
    imgs = json.loads(os.environ.get('IMAGES', '[]'))
    if not imgs:
        return html
    st = S3Storage(request=None)
    for im in imgs:
        key = f"{proj.workspace_id}/{uuid.uuid4().hex}-{im['name']}"
        with open(im['remote'], 'rb') as fh:
            if not st.upload_file(fh, key, 'image/png'):
                raise SystemExit('อัปโหลดรูปไม่สำเร็จ ' + im['name'])
        size = os.path.getsize(im['remote'])
        a = FileAsset.objects.create(asset=key, workspace_id=proj.workspace_id, project=proj, page=p,
                                     entity_type='PAGE_DESCRIPTION', entity_identifier=str(p.id), is_uploaded=True,
                                     size=size, attributes={'name': im['name'], 'type': 'image/png', 'size': size},
                                     created_by=p.owned_by, updated_by=p.owned_by)
        w = min(im['w'] / 2, 720)          # ภาพ render ที่ 2x
        h = w * im['h'] / im['w']
        tag = (f'<image-component src="{a.id}" width="{w:.0f}px" height="{h:.0f}px" '
               f'id="{uuid.uuid4()}" aspectratio="{im["w"] / im["h"]}"></image-component>')
        html = re.sub(r'<p>\\s*<img[^>]*src="' + re.escape(im['ref']) + r'"[^>]*>\\s*</p>', tag, html)
        html = re.sub(r'<img[^>]*src="' + re.escape(im['ref']) + r'"[^>]*>', tag, html)
        print('แนบรูป', im['name'], a.id)
    return html
"""

LIST = PRELUDE + """
proj = Project.objects.get(name=os.environ['PROJECT'])
for p in Page.objects.filter(projects=proj).order_by('-updated_at'):
    print(p.id, '|', p.name, '|', p.updated_at.date(), '| access', p.access)
"""

CREATE = PRELUDE + """
html = open(os.environ['HTML_PATH'], encoding='utf-8').read()
proj = Project.objects.get(name=os.environ['PROJECT'])
ref = Page.objects.filter(projects=proj).order_by('created_at').first()
if ref is None:
    raise SystemExit('โปรเจกต์นี้ยังไม่มี page ให้ก๊อปสิทธิ์/เจ้าของ — สร้าง page แรกจากหน้าเว็บก่อน')
p = Page.objects.create(workspace=proj.workspace, name=os.environ['NAME'], description_html=html,
                        description_stripped=strip(html), owned_by=ref.owned_by, created_by=ref.owned_by,
                        updated_by=ref.owned_by, access=ref.access)
ProjectPage.objects.create(workspace=proj.workspace, project=proj, page=p, created_by=ref.owned_by, updated_by=ref.owned_by)
p.description_html = attach_images(p, proj, html)
p.save()
print('สร้างแล้ว', p.id, '|', p.name)
"""

UPDATE = PRELUDE + """
html = open(os.environ['HTML_PATH'], encoding='utf-8').read()
p = Page.objects.get(id=os.environ['PAGE_ID'])
proj = ProjectPage.objects.filter(page=p).first().project
html = attach_images(p, proj, html)
p.description_html = html
p.description_stripped = strip(html)
p.description_binary = None   # ให้ editor โหลดใหม่จาก HTML
p.description_json = {}
if os.environ.get('NAME'):
    p.name = os.environ['NAME']
p.save()
print('อัปเดตแล้ว', p.id, '|', p.name)
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("markdown", nargs="?")
    ap.add_argument("--project")
    ap.add_argument("--name")
    ap.add_argument("--page-id")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()

    if a.list:
        return django(LIST, {"PROJECT": a.project or sys.exit("--list ต้องมี --project")})
    if not a.markdown:
        sys.exit("ต้องระบุไฟล์ markdown")

    check = os.path.join(os.path.dirname(__file__), "check.sh")
    if subprocess.run([check, a.markdown]).returncode != 0:
        sys.exit("check.sh ไม่ผ่าน — แก้ก่อนนำขึ้น (หรือรันซ้ำด้วย SKIP_CHECK=1 ถ้าตั้งใจ)") if not os.environ.get("SKIP_CHECK") else None

    src = open(a.markdown, encoding="utf-8").read()
    src = re.sub(r"\A---\n.*?\n---\n", "", src, flags=re.S)  # ตัด frontmatter
    workdir = tempfile.mkdtemp(prefix="page_")
    src, images = prepare_images(src, os.path.dirname(os.path.abspath(a.markdown)), workdir)
    html = md_to_html(src)

    rdir = f"/tmp/page_{os.getpid()}"
    subprocess.run(["docker", "exec", CONTAINER, "mkdir", "-p", rdir], check=True)
    hp = os.path.join(workdir, "page.html")
    open(hp, "w", encoding="utf-8").write(html)
    subprocess.run(["docker", "cp", hp, f"{CONTAINER}:{rdir}/page.html"], check=True, capture_output=True)
    for i, im in enumerate(images):
        im["remote"] = f"{rdir}/img{i}.png"
        subprocess.run(["docker", "cp", im["path"], f"{CONTAINER}:{im['remote']}"], check=True, capture_output=True)
    env = {"HTML_PATH": f"{rdir}/page.html", "IMAGES": json.dumps(images, ensure_ascii=False)}
    try:
        if a.page_id:
            django(UPDATE, {**env, "PAGE_ID": a.page_id, "NAME": a.name or ""})
        else:
            if not (a.project and a.name):
                sys.exit("สร้างใหม่ต้องมี --project และ --name")
            django(CREATE, {**env, "PROJECT": a.project, "NAME": a.name})
    finally:
        subprocess.run(["docker", "exec", CONTAINER, "rm", "-rf", rdir])


if __name__ == "__main__":
    main()

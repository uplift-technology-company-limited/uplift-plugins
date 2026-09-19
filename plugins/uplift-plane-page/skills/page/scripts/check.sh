#!/usr/bin/env bash
# ตรวจ markdown ก่อนนำขึ้น Plane page: นับลูกศร ขีดยาว จุดคั่นยาว mermaid และบรรทัดยาว
# ใช้: check.sh page.md   (exit 1 ถ้ามีเรื่องต้องแก้)
set -uo pipefail
f="${1:?ใช้: check.sh <ไฟล์.md>}"
[ -f "$f" ] || { echo "ไม่พบไฟล์ $f"; exit 2; }

# ไม่นับในบล็อกโค้ดและในแถวตาราง (ตารางใช้ลูกศรเป็น "จาก/ไป" ได้)
body=$(awk '/^```/{c=!c; next} !c && !/^\|/' "$f")

arrows=$(printf '%s' "$body" | grep -o '→\|->\|⇒' | wc -l)
dashes=$(printf '%s' "$body" | grep -o '—\|–' | wc -l)
dots=$(printf '%s' "$body" | grep -c '·.*·.*·.*·')
wiki=$(printf '%s' "$body" | grep -o '\[\[[^]]*\]\]' | wc -l)
mermaid=$(grep -c '^```mermaid' "$f")
long=$(printf '%s' "$body" | python3 -c 'import sys; print(sum(1 for l in sys.stdin if len(l.rstrip("\n"))>220))')

bad=0
report() { printf '%-34s %4s  %s\n' "$1" "$2" "$3"; [ "$2" -gt 0 ] && bad=1; }
report "ลูกศร → -> ⇒ (นอกตาราง/โค้ด)" "$arrows" "เขียนเป็นคำเชื่อม หรือรายการลำดับเลข"
report "ขีดยาว — –" "$dashes" "ขึ้นประโยคใหม่ หรือใช้ 'คือ' / วงเล็บ"
report "ลิงก์ Obsidian [[...]]" "$wiki" "Plane ไม่รู้จัก ขึ้นเป็นวงเล็บดิบ · เขียนเป็นชื่อเอกสารเต็ม + อยู่ที่ไหน หรือลิงก์ page จริง"
report "บรรทัดที่มี · เกิน 3 ตัว" "$dots" "แตกเป็น bullet หรือตาราง"
printf '%-34s %4s  %s\n' "บล็อก mermaid (จะ render เป็นภาพ)" "$mermaid" "publish.py แปลงเป็น PNG ให้เอง · ข้อความรอบภาพยังต้องอ่านรู้เรื่องโดยไม่ต้องดูภาพ"
report "บรรทัดยาวเกิน 220 ตัวอักษร" "$long" "ตัดเป็นหลายประโยค"

if [ "$bad" -eq 1 ]; then
  echo; echo "ตัวอย่างบรรทัดที่ต้องแก้:"
  printf '%s\n' "$body" | grep -n '→\|->\|⇒\|—\|–\|\[\[' | head -8 | cut -c1-160
  exit 1
fi
echo "ผ่าน"

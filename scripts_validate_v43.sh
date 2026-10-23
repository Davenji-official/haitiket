#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
"$ROOT/scripts_validate_v42.sh"
python3 - "$ROOT" <<'PY'
import sys
from pathlib import Path
r=Path(sys.argv[1])
checks={
 'migration exists': (r/'supabase/migrations/0039_global_announcements_v43.sql').is_file(),
 'publish RPC admin protected': "not public.admin_unlocked()" in (r/'supabase/migrations/0039_global_announcements_v43.sql').read_text(),
 'publish RPC audit log': 'publish_global_announcement' in (r/'supabase/migrations/0039_global_announcements_v43.sql').read_text(),
 'admin message tab': 'AdminAnnouncementsTab()' in (r/'lib/ui/admin_screen.dart').read_text(),
 'admin publish uses RPC': 'admin_publish_announcement' in (r/'lib/data/repo.dart').read_text(),
 'global banner in shell': 'globalAnnouncement()' in (r/'lib/ui/shell.dart').read_text(),
 'FIBRAXA branding in shell': 'Powered by FIBRAXA' in (r/'lib/ui/shell.dart').read_text(),
 'FIBRAXA branding on splash': 'Powered by FIBRAXA' in (r/'lib/ui/splash.dart').read_text(),
 'GIF MIME support': "'gif': 'image/gif'" in (r/'lib/ui/screens7.dart').read_text(),
 'GIF original bytes preserved': 'final xs = await picker.pickMultiImage();' in (r/'lib/ui/screens7.dart').read_text(),
 'GIF allowed in storage bucket': "'image/gif'" in (r/'supabase/migrations/0039_global_announcements_v43.sql').read_text(),
 'dashboard chart present': "chart('Diagramme des commandes'" in (r/'lib/ui/admin2.dart').read_text(),
}
failed=[name for name,ok in checks.items() if not ok]
for name,ok in checks.items(): print(('OK' if ok else 'FAIL')+': '+name)
if failed: raise SystemExit(1)
print('V43 static checks: OK. Apply migration and verify Supabase Realtime plus Flutter builds/tests before production.')
PY

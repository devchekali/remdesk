#!/usr/bin/env bash
# Applique l'identite RemDesk sur les sources RustDesk, apres checkout des sous-modules.
# Idempotent autant que possible, et FAIL si une cible attendue est absente : mieux vaut
# une CI rouge qu'un binaire qui repart en silence sur le serveur public.
set -euo pipefail

HOST="srv.remdesk.tech"
KEY="pxP546emPmKIqj+0Aykan3mYOeZxxIQOY9hEgGs+cSM="
APP="RemDesk"

cfg="libs/hbb_common/src/config.rs"
rc="flutter/windows/runner/Runner.rc"

must_replace() {  # fichier  motif_grep  sed_expr  libelle
  local file="$1" needle="$2" expr="$3" label="$4"
  grep -q "$needle" "$file" || { echo "REBRAND: motif absent ($label) dans $file"; exit 1; }
  sed -i "$expr" "$file"
  echo "REBRAND: $label applique"
}

# 1. Serveur et cle, en dur (le coeur : sans ca, rien n'est fait)
must_replace "$cfg" 'rs-ny.rustdesk.com' \
  "s|pub const RENDEZVOUS_SERVERS: &\[&str\] = &\[\"rs-ny.rustdesk.com\"\];|pub const RENDEZVOUS_SERVERS: \&[\&str] = \&[\"$HOST\"];|" \
  "serveur de rendez-vous"
must_replace "$cfg" 'OeVuKk5nlHiXp' \
  "s|pub const RS_PUB_KEY: &str = \"[^\"]*\";|pub const RS_PUB_KEY: \&str = \"$KEY\";|" \
  "cle publique"

# 2. Nom applicatif (titre de fenetre, dossier de config, service, registre)
must_replace "$cfg" 'RwLock::new("RustDesk"' \
  "s|RwLock::new(\"RustDesk\".to_owned())|RwLock::new(\"$APP\".to_owned())|" \
  "APP_NAME"

# 3. Proprietes du binaire Windows (clic droit > Proprietes > Details)
must_replace "$rc" 'RustDesk Remote Desktop' \
  's|"RustDesk Remote Desktop"|"RemDesk Remote Support"|' "FileDescription"
must_replace "$rc" 'VALUE "ProductName", "RustDesk"' \
  's|VALUE "ProductName", "RustDesk"|VALUE "ProductName", "RemDesk"|' "ProductName"

# 4. Verification finale : la cle et le serveur sont bien dans le binaire a compiler
grep -q "$HOST" "$cfg" && grep -q "$KEY" "$cfg" || { echo "REBRAND: verification finale echouee"; exit 1; }
echo "REBRAND: identite RemDesk appliquee ($HOST)"

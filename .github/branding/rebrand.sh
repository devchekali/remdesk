#!/usr/bin/env bash
# Applique l'identite RemDesk / Chekali Automation sur les sources RustDesk,
# apres checkout des sous-modules. FAIL si une cible attendue est absente :
# mieux vaut une CI rouge qu'un binaire qui repart en silence sur le serveur public.
set -euo pipefail

HOST="srv.remdesk.tech"
KEY="pxP546emPmKIqj+0Aykan3mYOeZxxIQOY9hEgGs+cSM="
APP="RemDesk"
SITE="chekali-automation.com"

cfg="libs/hbb_common/src/config.rs"
rc="flutter/windows/runner/Runner.rc"
common="flutter/lib/common.dart"
home="flutter/lib/desktop/pages/desktop_home_page.dart"

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

# 4. Charte graphique Chekali Automation (bleu navy)
must_replace "$common" '0xFF0071FF' \
  's|Color(0xFF0071FF)|Color(0xFF0B2447)|' "couleur accent"
must_replace "$common" '0x770071FF' \
  's|Color(0x770071FF)|Color(0x770B2447)|' "accent 50%"
must_replace "$common" '0xAA0071FF' \
  's|Color(0xAA0071FF)|Color(0xAA0B2447)|' "accent 80%"
must_replace "$common" '0xFF2C8CFF' \
  's|Color(0xFF2C8CFF)|Color(0xFF163460)|' "couleur bouton survol"
# logo un peu plus grand dans le panneau (max 60 -> 88 px de haut)
must_replace "$common" 'maxWidth: 300, maxHeight: 60' \
  's|maxWidth: 300, maxHeight: 60|maxWidth: 300, maxHeight: 88|' "taille logo"

# 5. Lien du site web sous l'intro
grep -q 'buildTip(context),' "$home" || { echo "REBRAND: ancre buildTip absente"; exit 1; }
if grep -q 'chekali-automation.com' "$home"; then
  echo "REBRAND: lien site deja present"
else
  HOME_FILE="$home" SITE="$SITE" python3 - <<'PYIN'
import os
p=os.environ["HOME_FILE"]; site=os.environ["SITE"]
s=open(p).read()
anchor="      buildTip(context),\n"
assert s.count(anchor)==1, "ancre buildTip non unique"
widget=(
"      buildTip(context),\n"
"      Align(\n"
"        alignment: Alignment.centerLeft,\n"
"        child: InkWell(\n"
"          onTap: () => launchUrl(Uri.parse('https://%s')),\n"
"          child: Text(\n"
"            '%s',\n"
"            style: TextStyle(\n"
"              color: MyTheme.accent,\n"
"              fontSize: 12,\n"
"              decoration: TextDecoration.underline,\n"
"            ),\n"
"          ),\n"
"        ).marginOnly(left: 20, right: 16, top: 2, bottom: 8),\n"
"      ),\n"
) % (site, site)
open(p,"w").write(s.replace(anchor,widget,1))
print("REBRAND: lien site web insere")
PYIN
fi

# 6. Verification finale
grep -q "$HOST" "$cfg" && grep -q "$KEY" "$cfg" || { echo "REBRAND: verification finale echouee"; exit 1; }
echo "REBRAND: identite RemDesk + charte Chekali appliquee ($HOST, $SITE)"

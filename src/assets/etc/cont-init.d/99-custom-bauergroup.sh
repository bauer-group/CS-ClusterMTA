#!/usr/bin/with-contenv bash

#Exit immediately if a command exits with a non-zero status.
set -e

#
# Configure BAUERGROUP Environment
#

# /opt/haraka-submission/config/ehlo_hello_message
cat << EOF > /opt/haraka-submission/config/ehlo_hello_message
BAUER GROUP SMTP Service
EOF

# /opt/haraka-smtp/config/ehlo_hello_message
cat << EOF > /opt/haraka-smtp/config/ehlo_hello_message
BAUER GROUP SMTP Service
EOF

# /opt/haraka-submission/config/smtpgreeting 
cat << EOF > /opt/haraka-submission/config/smtpgreeting 
Server (BAUER GROUP)
EOF

# /opt/haraka-smtp/config/smtpgreeting 
cat << EOF > /opt/haraka-smtp/config/smtpgreeting 
Server (BAUER GROUP)
EOF

# /opt/haraka-submission/config/connection_close_message 
cat << EOF > /opt/haraka-submission/config/connection_close_message 
2.0.0 Goodbye from BAUER GROUP
EOF

# /opt/haraka-smtp/config/connection_close_message 
cat << EOF > /opt/haraka-smtp/config/connection_close_message 
2.0.0 Goodbye from BAUER GROUP
EOF

# /opt/admin/src/Base/Config/Brand.php
brandFile="/opt/admin/src/Base/Config/Brand.php"
# Prüfe, ob die Datei existiert
if [ -f "$brandFile" ]; then    
    sed -i 's/private \$brandName = "poste.io";/private \$brandName = "BAUER GROUP";/g' $brandFile
fi

# Definiere ein Array mit den Pfaden zu den Verzeichnissen
templatePaths=("/opt/admin/templates" "/opt/admin/templates/Base/Security")

# Durchlaufe das Array und suche in jedem Verzeichnis nach .twig Dateien, dann ersetze `is_pro()` durch `true`
for path in "${templatePaths[@]}"; do
    find "$path" -maxdepth 1 -type f -name "*.twig" -print0 | while IFS= read -r -d $'\0' file; do
        sed -i 's/is_pro()/true/g' "$file"
    done
done

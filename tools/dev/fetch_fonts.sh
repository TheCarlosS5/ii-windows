#!/usr/bin/env bash
# Downloads the fonts illogical-impulse uses, from their official repositories, into third_party/fonts.
set -euo pipefail
cd "$(dirname "$0")/../../third_party"
mkdir -p fonts-src fonts && cd fonts-src
dl() { curl -sfL -o "$2" "$1"; echo "ok $2"; }
[ -d gsf ] || git clone -q --depth 1 https://github.com/end-4/google-sans-flex.git gsf
dl 'https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D.ttf' 'MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf'
dl 'https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsOutlined%5BFILL,GRAD,opsz,wght%5D.ttf' 'MaterialSymbolsOutlined[FILL,GRAD,opsz,wght].ttf'
dl 'https://github.com/google/fonts/raw/main/ofl/readexpro/ReadexPro%5BHEXP,wght%5D.ttf' 'ReadexPro[HEXP,wght].ttf'
dl 'https://github.com/google/fonts/raw/main/ofl/spacegrotesk/SpaceGrotesk%5Bwght%5D.ttf' 'SpaceGrotesk[wght].ttf'
dl 'https://github.com/google/fonts/raw/main/ofl/rubik/Rubik%5Bwght%5D.ttf' 'Rubik[wght].ttf'
dl 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz' JetBrainsMono.tar.xz
mkdir -p jbm && tar -xJf JetBrainsMono.tar.xz -C jbm
cd ..
cp fonts-src/gsf/*.ttf fonts/ && cp fonts-src/gsf/LICENSE fonts/LICENSE-GoogleSansFlex-OFL.txt
cp fonts-src/Material*.ttf fonts-src/ReadexPro*.ttf fonts-src/SpaceGrotesk*.ttf fonts-src/Rubik*.ttf fonts/
cp fonts-src/jbm/JetBrainsMonoNerdFont-{Regular,Bold,Italic,Medium,SemiBold}.ttf fonts/
curl -sfL -o fonts/LICENSE-MaterialSymbols-Apache2.txt https://raw.githubusercontent.com/google/material-design-icons/master/LICENSE
curl -sfL -o fonts/LICENSE-GoogleFonts-OFL.txt https://raw.githubusercontent.com/google/fonts/main/ofl/rubik/OFL.txt
curl -sfL -o fonts/LICENSE-JetBrainsMono-OFL.txt https://raw.githubusercontent.com/JetBrains/JetBrainsMono/master/OFL.txt
echo "fonts ready in third_party/fonts"

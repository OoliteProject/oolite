# No parameters: build both clang and gcc in that order (end setup will be for gcc)
# One parameter gcc = build gcc only (end setup will be for gcc)
# One parameter clang = build clang only (end setup will be for clang)

source ../common/check_rename_fn.sh

install() {
	# First parameter is package name
	# Second optional parameter is gcc or clang
    echo "Installing $1 package"

    if [ -z "$2" ]; then
		fullname=$1
    else
		fullname="${1}_${2}"
    fi

    packagename="$MINGW_PACKAGE_PREFIX-$fullname*any.pkg.tar.zst"
	filename=$(ls $packagename 2>/dev/null)

	# package file eg. mingw-w64-x86_64-libobjc2-2.3-3-any.pkg.tar.zst
    if [ -z "$filename" ]; then
        echo "❌ No file matching $packagename found." >&2
        exit 1
    fi

    if ! pacman -U $filename --noconfirm ; then
	    echo "❌ $filename install failed!" >&2
	    exit 1
	fi
}

move_installer() {
	# First parameter is gcc or clang
	
	cd installers/win32
	read filename fullname <<< "$(check_rename "OoliteInstall" "OoliteInstall-*" $1)"
	mv $filename ../../../installer/
	cd ../..
}

build_oolite() {
	# First parameter is gcc or clang

	pacman -Q > installer/installed-packages-$1.txt
	source $MINGW_PREFIX/share/GNUstep/Makefiles/GNUstep.sh

	cd oolite
	make -f Makefile clean
	if make -f Makefile release -j$(nproc); then
		echo "✅ Oolite build completed successfully"
	else
		echo "❌ Oolite build failed" >&2
		exit 1
	fi
	make -f Makefile pkg-win
	move_installer $1

	make -f Makefile clean
	if make -f Makefile release-deployment -j$(nproc); then
		echo "✅ Oolite build completed successfully"
	else
		echo "❌ Oolite build failed" >&2
		exit 1
	fi
	make -f Makefile pkg-win-deployment
	move_installer $1
	cd ..
}

pacman -S dos2unix --noconfirm
pacman -S pactoys --noconfirm
pacboy -S binutils --noconfirm
pacboy -S uutils-coreutils --noconfirm

cd packages
echo "Installing common libraries"
package_names=(spidermonkey SDL)
for packagename in "${package_names[@]}"; do
	install $packagename
done
cd ..

pacman -S git --noconfirm
pacboy -S libpng --noconfirm
pacboy -S openal --noconfirm
pacboy -S libvorbis --noconfirm
pacboy -S pcaudiolib --noconfirm 
pacboy -S espeak-ng --noconfirm
pacman -S make --noconfirm
pacboy -S nsis --noconfirm

rm -rf oolite
git clone -b modern_build https://github.com/mcarans/oolite.git
cd oolite
cp .absolute_gitmodules .gitmodules
git submodule update --init
git checkout -- .gitmodules
cd ..

rm -rf installer
mkdir installer

if [[ -z "$1" || "$1" == "clang" ]]; then
	pacboy -S clang --noconfirm
	pacboy -S lld --noconfirm

	cd packages
	echo "Installing GNUStep libraries with clang"
	export cc=$MINGW_PREFIX/bin/clang
	export cxx=$MINGW_PREFIX/bin/clang++
	clang_package_names=(libobjc2 gnustep-make gnustep-base)
	for packagename in "${clang_package_names[@]}"; do
		install $packagename clang
	done
	cd ..
	build_oolite clang
else
	cd packages
	echo "Installing GNUStep libraries with gcc"
	export cc=$MINGW_PREFIX/bin/gcc
	export cxx=$MINGW_PREFIX/bin/g++
	gcc_package_names=(gnustep-make gnustep-base)
	for packagename in "${gcc_package_names[@]}"; do
		install $packagename gcc
	done
	cd ..
	build_oolite gcc
fi

echo 'source $MINGW_PREFIX/share/GNUstep/Makefiles/GNUstep.sh' > /etc/profile.d/GNUstep.sh

if ! grep -q "# Custom history settings" ~/.bashrc; then
  cat >> ~/.bashrc <<'EOF'

# Custom history settings
WIN_HOME=$(cygpath "$USERPROFILE")
export HISTFILE=$WIN_HOME/.bash_history
export HISTSIZE=5000
export HISTFILESIZE=10000
shopt -s histappend
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"
EOF
fi

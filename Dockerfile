FROM elv13/old_gentoo

# Bypass tools that attempt to "optimize" flags
ENV CXX="g++ -static-libgcc -static-libstdc++"

ENV LDFLAGS="-static-libstdc++ -fuse-linker-plugin -Wl,--gc-sections -Wl,--strip-all -Wl,--as-needed"
ENV CXXFLAGS="-Os -ffunction-sections -fdata-sections -Wl,--gc-sections -Wl,--strip-all"
ENV CFLAGS="-Os -ffunction-sections -fdata-sections -Wl,--gc-sections -Wl,--strip-all"
#ENV LDFLAGS="-static-libstdc++ -flto -O -fuse-linker-plugin -Wl,--gc-sections"
#ENV CXXFLAGS="-ffunction-sections -fdata-sections -flto -Wl,--gc-sections"
#ENV CFLAGS="-ffunction-sections -fdata-sections -flto -Wl,--gc-sections"

RUN emerge --sync
RUN eselect python set 1

ADD make.conf /etc/portage/

#RUN echo '>=sys-libs/glibc-2.18' >> /etc/portage/package.mask/package.mask

#ENV FEATURES="-sandbox -usersandbox"
#ENV USE="static static-libs"

# It's part of the profile, not muc to do
RUN echo net-misc/openssh -static >> /etc/portage/package.use

RUN cat /etc/portage/make.conf

RUN echo '<=sys-devel/gcc-9' >> /etc/portage/package.unmask
RUN echo '<=sys-devel/gcc-9 **' >> /etc/portage/package.keywords

RUN emerge gcc
RUN binutils-config --linker ld.gold
RUN gcc-config `gcc-config -l | wc -l`

RUN PYTHON_SINGLE_TARGET="python3_2" USE="-xattr -rsync-verify" emerge portage

RUN emerge binutils && \
    emerge -C '=sys-devel/binutils-2.23*' '=sys-devel/binutils-2.28*'
RUN USE="static-libs X xkb" emerge x11-libs/libxkbcommon x11-libs/libxcb

#RUN emerge -e @world --update || echo Failed, but keep going

# Select the new GCC and rebuild
RUN gcc-config `gcc-config -l | wc -l`
RUN emerge -e @world || echo 'Failed, but keep going (self host)'

# Enable loop optimization and rebuild
#ENV USE="graphite lto"
#RUN emerge -e @world || echo 'Failed, but keep going (self host, poly)'
#RUN echo  'CFLAGS="$CFLAGS -fgraphite-identity -fgraphite -floop-interchange -ftree-loop-distribution -floop-strip-mine -floop-block"' >> /etc/portage/make.conf
#RUN echo  'CXXFLAGS="$CFLAGS"' >> /etc/portage/make.conf

# Enable LTO and rebuild
#RUN echo 'CFLAGS="$CFLAGS -flto=8"' >> /etc/portage/make.conf
#RUN echo 'CXXFLAGS="$CFLAGS"' >> /etc/portage/make.conf
#RUN echo 'LDFLAGS="-flto=8 $LDFLAGS"' >> /etc/portage/make.conf
#RUN emerge -e @world || echo 'Failed, but keep going (self host, LTO)'

RUN cat /etc/portage/make.conf

# Download Qt in order to build a minimal library
RUN wget https://download.qt.io/archive/qt/5.12/5.12.1/single/qt-everywhere-src-5.12.1.tar.xz
RUN tar -xpvf qt-everywhere-src-5.12.1.tar.xz

# Qt5 needs the Gl API
RUN emerge mesa freeglut dev-python/common

# Replace the default performance Qt flags for portability ones
RUN sed 's/-O3/-Os/' -i /qt-everywhere-src-5.12.1/qtbase/mkspecs/common/qcc-base.conf
RUN sed 's/-O2/-Os/' -i /qt-everywhere-src-5.12.1/qtbase/mkspecs/common/qcc-base.conf
RUN sed 's/-O3/-Os/' -i /qt-everywhere-src-5.12.1/qtbase/mkspecs/common/gcc-base.conf
RUN sed 's/-O2/-Os/' -i /qt-everywhere-src-5.12.1/qtbase/mkspecs/common/gcc-base.conf
RUN echo 'QMAKE_CXXFLAGS -=-O3' >> /qt-everywhere-src-5.12.1/qtbase/mkspecs/linux-g++/qmake.conf
RUN echo 'QMAKE_CXXFLAGS_RELEASE -=-O3' >> /qt-everywhere-src-5.12.1/qtbase/mkspecs/linux-g++/qmake.conf
RUN echo 'QMAKE_CXXFLAGS -=-O2' >> /qt-everywhere-src-5.12.1/qtbase/mkspecs/linux-g++/qmake.conf
RUN echo 'QMAKE_CXXFLAGS_RELEASE -=-O2' >> /qt-everywhere-src-5.12.1/qtbase/mkspecs/linux-g++/qmake.conf
RUN echo 'QMAKE_CXXFLAGS=-Os' >> /qt-everywhere-src-5.12.1/qtbase/mkspecs/linux-g++/qmake.conf
RUN echo 'QMAKE_CXXFLAGS_RELEASE=-Os' >> /qt-everywhere-src-5.12.1/qtbase/mkspecs/linux-g++/qmake.conf
RUN find /qt-everywhere-src-5.12.1/ | xargs grep O3 2> /dev/null \
 | grep -v xml | grep -v Binary 2> /dev/null | cut -f1 -d ':' \
 | grep -E '\.(conf|mk|sh|am|in)$' | xargs sed -i 's/O3/Os/'

# Build a static Qt package with as little system dependencies as
# possible
RUN cd qt-everywhere-src-5.12.1 &&\
  ./configure -v -release -opensource -confirm-license -reduce-exports -ssl \
   -xcb -xkbcommon -feature-accessibility -opengl desktop  -static -nomake examples \
   -nomake tests -skip qtwebengine -skip qtscript -skip qt3d -skip qtandroidextras \
   -skip qtwebview -skip qtwebsockets -skip qtdoc -skip qtcharts \
   -skip qtdatavis3d -skip qtgamepad -skip qtmultimedia -skip qtsensors \
   -skip qtserialbus -skip qtserialport -skip qtwebchannel -skip qtwayland \
   -prefix /opt/usr -no-glib -qt-zlib -qt-freetype -ltcg -optimize-size



# Build Qt, this is long
RUN cd qt-everywhere-src-5.12.1 && make -j8
RUN cd qt-everywhere-src-5.12.1 && make install
RUN rm -rf qt-e # Keep the docker image smaller

# Not very clean, but running tests in this environment hits a lot of
# bugs due to the unexpected static linkage.
RUN rm /opt/usr/lib/cmake/Qt5Test/Qt5TestConfig.cmake

#HACK Fix a regression
ADD GenerateExportHeader.cmake /usr/share/cmake/Modules/GenerateExportHeader.cmake

# Set some variable before bootstrapping KF5
ENV Qt5_DIR=/opt/usr/
ENV CMAKE_PREFIX_PATH=/opt/usr/
RUN QT_INSTALL_PREFIX=/opt/usr/

# Begin building KF5
#RUN apt install gperf gettext libxcb-keysyms1-dev libxrender-dev \
# libxcb-image0-dev libxcb-xinerama0-dev flex bison -y
RUN USE="-gpg -pcre -perl -python -threads -webdav -pcre-jit" emerge gperf gettext \
 flex bison x11-libs/xcb-util-keysyms dev-vcs/git yasm \
 media-libs/alsa-lib net-dns/libidn2 nettle

RUN git clone https://anongit.kde.org/extra-cmake-modules
RUN cd extra-cmake-modules && mkdir build && cd build && cmake .. \
 -DCMAKE_INSTALL_PREFIX=/ && make -j8 install

RUN mkdir -p /bootstrap/build

RUN mkdir /opt/ring-kde.AppDir -p

# This is necessary to build Ring with Pulse and video accel
# **WARNING** This has to be executed AFTER Qt has been installed to
# avoid poluting the system with versions of those packages
#RUN apt install libvdpau-dev libva-dev gettext autopoint libasound-dev \
# libpulse-dev libudev-dev wget libdbus-1-dev -y



# Fetch the ring library (without the daemon)
RUN git clone https://github.com/savoirfairelinux/ring-daemon --progress --verbose

# Add the patch now as the daemon use them
ADD patches /bootstrap/patches

RUN cd ring-daemon && git apply --reject --whitespace=fix /bootstrap/patches/ring-daemon.patch || echo 0

RUN mkdir -p ring-daemon/contrib/native && cd ring-daemon/contrib/native &&\
 CXXFLAGS=" -ffunction-sections -fdata-sections  -Wno-error=unused-result -Wno-unused-result -Os" \
 CFLAGS=" -ffunction-sections -fdata-sections  -Wno-error=unused-result -Wno-unused-result -Os" ../bootstrap \
   --disable-dbus-cpp --enable-vorbis --enable-opus --enable-zlib\
   --enable-uuid --enable-uuid --enable-pcre

# Try to force it to retry again and again until it works
RUN cd ring-daemon/contrib/native && \
   while [ true ]; do \
       make fetch-all -j8 && break || sleep 1800; \
   done

RUN emerge yasm
#RUN CFLAGS="" LDFLAGS="" emerge sys-fs/fuse

# TODO remove
#ENV LDFLAGS="-flto=8 $LDFLAGS"
#ENV CFLAGS="-flto=8 $CFLAGS"
#ENV CXXFLAGS="$CFLAGS"

ENV AR="/usr/bin/gcc-ar"
ENV NM="/usr/bin/gcc-nm"
ENV RANLIB="/usr/bin/gcc-ranlib"

#HACK Fix msgpack until the PR is merged
RUN cd ring-daemon/contrib/native && make msgpack || echo Ignore2
RUN sed -i 's/-Werror//' /ring-daemon/contrib/native/msgpack/CMakeLists.txt
RUN sed -i 's/-Werror//' /ring-daemon/contrib/native/msgpack/CMakeLists.txt
RUN sed -i 's/-O3/-Os/' /ring-daemon/contrib/native/msgpack/CMakeLists.txt
RUN sed -i 's/-O3/-Os/' /ring-daemon/contrib/native/msgpack/CMakeLists.txt

# Cross compile hack
RUN cd ring-daemon/contrib/native && CXXFLAGS="-Wno-error=unused-result \
 -Wno-unused-result -Os -ffunction-sections -fdata-sections " \
  CFLAGS="-Os -Wno-error=unused-result -Wno-unused-result -ffunction-sections\
  -fdata-sections " make -j8 || echo ignore2 #HACK
RUN cp /usr/share/libtool/build-aux/config.guess /ring-daemon/contrib/native/uuid/
RUN cp /usr/share/libtool/build-aux/config.sub /ring-daemon/contrib/native/uuid/

#HACK!!!!!
RUN cd ring-daemon/contrib/native &&\
 ../bootstrap --disable-dbus-cpp  \
   --enable-opus --enable-zlib --enable-uuid --enable-uuid && make fetch-all

# Build all the static dependencies
RUN cd ring-daemon/contrib/native && make -j8

# Compile the daemon. Pulse is disabled for now because it pulls
# too many dependencies are cause libring to link to them...
RUN cd ring-daemon &&  ./autogen.sh && ./configure --without-dbus \
 --enable-static --without-pulse --disable-vdpau --disable-vaapi \
 --disable-videotoolbox --disable-vda --disable-accel --disable-shared \
 --prefix=/opt/ring-kde.AppDir && make -j8

# Only add the file after the Daemon is built to speedup image creation
ADD CMakeLists.txt /bootstrap/CMakeLists.txt
ADD CMakeRingWrapper.txt.in /bootstrap/CMakeRingWrapper.txt.in
ADD CMakeWrapper.txt.in /bootstrap/CMakeWrapper.txt.in
ADD cmake /bootstrap/cmake

RUN cd /bootstrap/build && wget http://launchpad.net/ubuntu/+archive/primary/+files/libdbusmenu-qt_0.9.3+16.04.20160218.orig.tar.gz

# Build all the frameworks and prepare Ring-KDE
RUN cd /bootstrap/build && CXXFLAGS="" LDFLAGS="" cmake .. -DCMAKE_INSTALL_PREFIX=/opt/ring-kde.AppDir\
 -DCMAKE_BUILD_TYPE=Release -DDISABLE_KDBUS_SERVICE=1 \
 -DRING_BUILD_DIR=/ring-daemon/src/ -Dring_BIN=/ring-daemon/src/.libs/libring.a -Wno-dev || echo Ignore


RUN sed -i 's/5\.[0-9][0-9]/5\.39/' /bootstrap/build/kirigami/kirigami/CMakeLists.txt
RUN sed -i 's/5\.[0-9][0-9]/5\.39/' /bootstrap/build/qqc2-desktop-style/qqc2-desktop-style/CMakeLists.txt
RUN cd /bootstrap/build && CXXFLAGS="" LDFLAGS="" cmake .. -DCMAKE_INSTALL_PREFIX=/opt/ring-kde.AppDir\
 -DCMAKE_BUILD_TYPE=Release -DDISABLE_KDBUS_SERVICE=1 -DUSE_STATIC_QT=ON\
 -DRING_BUILD_DIR=/ring-daemon/src/ -Dring_BIN=/ring-daemon/src/.libs/libring.a -Wno-dev || echo Ignore


# Add the appimages
RUN wget "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
RUN chmod a+x appimagetool-x86_64.AppImage

# Enable LTO for some ring dependencies
ENV LDFLAGS="-static-libstdc++ -fuse-linker-plugin -Wl,--gc-sections -Wl,--strip-all -Wl,--as-needed -Wl,-flto=8"
ENV CFLAGS="-Os -ffunction-sections -fdata-sections -Wl,--gc-sections -Wl,--strip-all -flto=8 -Wl,-flto=8"
ENV CXXFLAGS="-Os -ffunction-sections -fdata-sections -Wl,--gc-sections -Wl,--strip-all -flto=8 -Wl,-flto=8"
RUN rm -rf /ring-daemon/contrib/native/samplerate/ /ring-daemon/contrib/native/.samplerate \
  /ring-daemon/contrib/native/nettle/ /ring-daemon/contrib/native/.nettle \
  /ring-daemon/contrib/native/pjpr* /ring-daemon/contrib/native/.pjp*
RUN cd /ring-daemon/contrib/native/ && make -j8

# Make sure there is fallback fonts and color Emojis
ADD fonts /fonts
RUN mkdir /opt/ring-kde.AppDir/fonts
ADD fonts/* /opt/ring-kde.AppDir/fonts/

# Fuse doesn't link with gold
RUN LDFLAGS="$LDFLAGS -Wl,-fuse-ld=bfd" emerge sys-fs/fuse

# Add the icons and desktop
RUN cp /bootstrap/build/ring-kde/ring-kde/data/*.desktop /opt/ring*/
RUN cp /bootstrap/build/ring-kde/ring-kde/data/icons/sc-apps-ring-kde.svgz \
  /opt/ring-kde.AppDir/ring-kde.svgz

ADD AppRun /opt/ring-kde.AppDir/

RUN sed -i 's/DBusActivatable=true/X-DBusActivatable=true/' -i /opt/ring-kde.AppDir/*.desktop

ADD AppRun /opt/ring-kde.AppDir/

ADD geticons.sh /
RUN git clone https://anongit.kde.org/breeze-icons /breeze-icons

CMD cd /bootstrap/build && make -j8 install && find /opt/ring-kde.AppDir/ \
  | grep -v ring-kde | xargs rm -rf &&\
   rm -rf /opt/ring-kde.AppDir/share/locale/ && /appimagetool-x86_64.AppImage\
  /opt/ring-kde.AppDir/ /export/ring-kde-$(date +%Y%m%d-%s).appimage

#CMAKE_AR=/usr/bin/gcc-ar CMAKE_CXX_ARCHIVE_CREATE="<CMAKE_AR> qcs <TARGET> <LINK_FLAGS> <OBJECTS>" CMAKE_CXX_ARCHIVE_FINISH=true NM=/usr/bin/gcc-nm AR=/usr/bin/gcc-ar RANLIB=/usr/bin/gcc-ranlib LDFLAGS="-Os -flto=8 -ffunction-sections -fdata-sections -static-libstdc++ -Wl,--export-dynamic" CXXFLAGS="-Os -flto=8 -ffunction-sections -fdata-sections -fvisibility=default -static-libgcc -static-libstdc++ -Wno-error=unused-result -Wno-unused-result" CFLAGS="-Os -flto=8 -Wno-error=unused-result -Wno-unused-result  -ffunction-sections -fdata-sections -Wno-error=unused-result -Wno-unused-result"

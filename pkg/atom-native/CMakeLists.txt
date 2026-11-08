# Atom.Native: the few things the rice shell needs that QML can't do on its own.
#   BlurBehind   KWin's blur under a set of rounded rects of a window, kept in step with a shape that moves
#   InputMask    the part of a window that takes the pointer (the rest lets clicks through to what's below)
#   Bus          one message bus for every widget in the process, whatever QML engine loaded it
# Built and installed per user (no root): ./build.sh puts the module in ~/.local/lib/qt6/qml/Atom/Native,
# which plasmashell finds through QML_IMPORT_PATH (systemd/plasma-plasmashell.service.d/rice.conf).
cmake_minimum_required(VERSION 3.22)
project(atom-native VERSION 0.1 LANGUAGES CXX)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Quick)
find_package(KF6WindowSystem REQUIRED)
qt_standard_project_setup(REQUIRES 6.8)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

qt_add_qml_module(atomnative
    URI Atom.Native
    VERSION 1.0
    PLUGIN_TARGET atomnative
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/Atom/Native
    SOURCES
        src/blurbehind.h src/blurbehind.cpp
        src/inputmask.h src/inputmask.cpp
        src/bus.h src/bus.cpp
        src/regions.h src/regions.cpp
)
target_include_directories(atomnative PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(atomnative PRIVATE Qt6::Core Qt6::Gui Qt6::Quick KF6::WindowSystem)

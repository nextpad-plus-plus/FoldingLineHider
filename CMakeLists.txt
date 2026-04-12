cmake_minimum_required(VERSION 3.20)
project(FoldingLineHider LANGUAGES CXX OBJCXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")
set(CMAKE_CXX_VISIBILITY_PRESET hidden)

set(NPP_MACOS_DIR "${CMAKE_SOURCE_DIR}/../../notepad-plus-plus-macos")
set(NPP_WIN_DIR "${CMAKE_SOURCE_DIR}/../../notepad-plus-plus")
set(SCINTILLA_INCLUDE "${NPP_WIN_DIR}/scintilla/include")
set(NPP_PLUGIN_INCLUDE "${NPP_MACOS_DIR}/src")

add_library(FoldingLineHider SHARED src/FoldingLineHider.mm)
target_include_directories(FoldingLineHider PRIVATE
    ${NPP_PLUGIN_INCLUDE}
    ${SCINTILLA_INCLUDE})
target_link_libraries(FoldingLineHider PRIVATE "-framework Cocoa")
set(PLUGIN_INSTALL_DIR "$ENV{HOME}/.notepad++/plugins/FoldingLineHider")
set_target_properties(FoldingLineHider PROPERTIES PREFIX "" SUFFIX ".dylib")
install(TARGETS FoldingLineHider DESTINATION "${PLUGIN_INSTALL_DIR}")

TEMPLATE = app
TARGET = tst_metalpresentation
QT -= gui
CONFIG += console c++17
CONFIG -= app_bundle
SOURCES += $$PWD/tst_metalpresentation.cpp
HEADERS += $$PWD/../../app/streaming/video/ffmpeg-renderers/metalpresentation.h

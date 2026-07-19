# Superseded iOS Portability Plan

Date: 2026-04-17

Status: Superseded by
[Milestone 31: macOS Retrench And Mobile Split](../../ROADMAP.md#milestone-31-macos-retrench-and-mobile-split).

This note is retained only as historical context for the earlier iOS portability
experiment. Do not treat it as evidence that the current `SpeakSwiftly` package
supports iOS.

The current direction is to keep `SpeakSwiftly` as a macOS-only local speech
worker package and pursue mobile speech in a separate `SpeakSwiftlyMobile` app.
As of SpeakSwiftly 12, normalization is an internal package target rather than
an independent dependency. The mobile app should begin with app-owned text
conditioning; extract a vended cross-platform normalization product only after
both apps prove a stable portable boundary.

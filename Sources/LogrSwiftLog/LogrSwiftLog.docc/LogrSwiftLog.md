# ``LogrSwiftLog``

A swift-log handler that records swift-log events, your dependencies' included, in a Logr service.

## Overview

Bootstrap swift-log once at launch with ``LogrLogHandler`` and the service the app logs to. Every event then
goes through the same level filter, storage, encryption and OSLog mirror as one logged through Logr directly.
Tag metadata values with ``LogrSensitivity`` to store them redacted.

## Topics

### Bridging swift-log

- ``LogrLogHandler``
- ``LogrSensitivity``

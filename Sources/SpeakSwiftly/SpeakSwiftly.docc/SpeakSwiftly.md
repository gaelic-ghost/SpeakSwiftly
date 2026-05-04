# ``SpeakSwiftly``

Generate live speech playback and retained audio artifacts from a shared runtime.

## Overview

SpeakSwiftly centers around a long-lived ``SpeakSwiftly/Runtime``. You create that runtime with ``SpeakSwiftly/liftoff(configuration:stateRootURL:)`` and then interact with focused handles instead of one large method surface.

Use ``SpeakSwiftly/Runtime/generate`` when you want to synthesize speech, ``SpeakSwiftly/Runtime/player`` when you want to inspect or control playback, ``SpeakSwiftly/Runtime/voices`` when you want to manage stored voice profiles, and ``SpeakSwiftly/Runtime/jobs`` or ``SpeakSwiftly/Runtime/artifacts`` when you want to inspect retained generation output.

If you need custom text normalization behavior, create a ``SpeakSwiftly/Normalizer`` up front and pass it through ``SpeakSwiftly/Configuration`` during startup.

## Topics

### Essentials

- ``SpeakSwiftly``
- ``SpeakSwiftly/liftoff(configuration:stateRootURL:)``
- ``SpeakSwiftly/Runtime``
- ``SpeakSwiftly/Configuration``

### Articles

- <doc:RuntimeQuickStart>
- <doc:RetainedArtifacts>
- <doc:VoiceProfileCreation>
- <doc:TextProfileManagement>
- <doc:WorkerContract>

### Generating Speech

- ``SpeakSwiftly/Generate``
- ``SpeakSwiftly/Generate/speech(text:voiceProfile:textProfile:sourceFormat:requestContext:qwenPreModelTextChunking:)``
- ``SpeakSwiftly/Generate/audio(text:voiceProfile:textProfile:sourceFormat:requestContext:)``
- ``SpeakSwiftly/Generate/batch(_:voiceProfile:)``
- ``SpeakSwiftly/RequestHandle``

### Voice Profiles

- ``SpeakSwiftly/Voices``
- ``SpeakSwiftly/ProfileSummary``
- ``SpeakSwiftly/Vibe``

### Playback And Observation

- ``SpeakSwiftly/Player``
- ``SpeakSwiftly/PlaybackState``
- ``SpeakSwiftly/RequestSnapshot``
- ``SpeakSwiftly/RequestUpdate``
- ``SpeakSwiftly/GenerationEventUpdate``

### Retained Output

- ``SpeakSwiftly/Jobs``
- ``SpeakSwiftly/GenerationJob``
- ``SpeakSwiftly/GenerationArtifact``
- ``SpeakSwiftly/Artifacts``

### Support

- ``SpeakSwiftly/Normalizer``
- ``SpeakSwiftly/SupportResources``

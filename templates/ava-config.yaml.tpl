llm:
  provider: openai-compatible
  base_url: ${OPENCLAW_URL}
  model: ${OPENCLAW_MODEL}
  temperature: 0.7
  max_tokens: 250

tts:
  provider: elevenlabs
  api_key: ${ELEVENLABS_API_KEY}
  voice_id: TxGEqnHWrfWFTfGW9XjX
  model: eleven_flash_v2_5
  stability: 0.5
  similarity_boost: 0.75

stt:
  provider: deepgram
  api_key: ${DEEPGRAM_API_KEY}
  model: nova-3
  language: de
  smart_format: true
  endpointing: 10

asterisk:
  ari_url: http://${PBX_HOST}:8088
  ari_username: ${ARI_USERNAME}
  ari_password: ${ARI_PASSWORD}
  audiosocket_host: 0.0.0.0
  audiosocket_port: ${AUDIOSOCKET_PORT}
  ami_host: ${PBX_HOST}
  ami_port: 5038
  ami_username: ${AMI_USERNAME}
  ami_password: ${AMI_PASSWORD}

call:
  max_duration_seconds: 1800
  silence_timeout_seconds: 20
  amd_enabled: true

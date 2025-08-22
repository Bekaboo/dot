require('magenta').setup({
  chimeVolume = 0,
  sidebarPosition = 'below',
  sidebarPositionOpts = {
    below = {
      displayHeightPercentage = 0.5,
      inputHeightPercentage = 0.1,
    },
  },
  profiles = {
    {
      name = 'gpt-5',
      model = 'gpt-5',
      provider = 'openai',
      fastModel = 'gpt-5-mini',
      apiKeyEnvVar = 'OPENAI_API_KEY',
    },
  },
  editPrediction = {
    profile = {
      provider = 'openai',
      model = 'gpt-5-mini',
      apiKeyEnvVar = 'OPENAI_API_KEY',
    },
  },
})

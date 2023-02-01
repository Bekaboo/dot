local palette = {}

palette.dark = {
  yellow       = '#e6bb86',
  earth        = '#c1a575',
  orange       = '#ffa569',
  pink         = '#dfa6a8',
  ochre        = '#e87c69',
  scarlet      = '#d85959',
  wine         = '#a52929',
  tea          = '#a4bd84',
  aqua         = '#79ada7',
  turquoise    = '#7fa0af',
  flashlight   = '#add0ef',
  skyblue      = '#a5d5ff',
  cerulean     = '#96bef7',
  lavender     = '#caafeb',
  purple       = '#a48fd1',
  magenta      = '#f481e3',
  pigeon       = '#8f9fbc',
  cumulonimbus = '#486a91',
  thunder      = '#385372',
  white        = '#e5e5eb',
  smoke        = '#bebec3',
  beige        = '#b1aca7',
  steel        = '#5e6379',
  iron         = '#313742',
  deepsea      = '#293950',
  ocean        = '#1f2b3b',
  jeans        = '#171d2b',
  space        = '#13161f',
  black        = '#09080b',

  tea_blend      = '#425858',
  aqua_blend     = '#293a44',
  purple_blend   = '#2e324b',
  lavender_blend = '#4d4d78',
  scarlet_blend  = '#4b2c38',
  wine_blend     = '#351f29',
  earth_blend    = '#303032',
  smoke_blend    = '#272d3a',
  pigeon_blend   = '#262e3e',
}

palette.light = {
  yellow       = '#a84a24',
  earth        = '#b48327',
  orange       = '#b48327',
  pink         = '#c27e81',
  ochre        = '#ba4e33',
  scarlet      = '#d85959',
  wine         = '#a52929',
  tea          = '#5a863c',
  aqua         = '#3b8f84',
  turquoise    = '#29647a',
  flashlight   = '#6ea6d0',
  skyblue      = '#4c99d4',
  cerulean     = '#3a6baf',
  lavender     = '#9d7bca',
  purple       = '#8b71c7',
  magenta      = '#ac4ea1',
  pigeon       = '#6666a8',
  cumulonimbus = '#486a91',
  thunder      = '#cac4bf',
  white        = '#385372',
  smoke        = '#404553',
  beige        = '#385372',
  steel        = '#989c8b',
  iron         = '#b8b7b3',
  deepsea      = '#c2b8b1',
  ocean        = '#cac4bf',
  jeans        = '#d9d6cf',
  space        = '#e2dfd7',
  black        = '#efefef',

  tea_blend      = '#b4bea5',
  aqua_blend     = '#bac2b8',
  purple_blend   = '#c6bcc8',
  lavender_blend = '#bab0c8',
  scarlet_blend  = '#C59E99',
  wine_blend     = '#cab1ab',
  earth_blend    = '#CBC0AC',
  smoke_blend    = '#B6B6B4',
  pigeon_blend   = '#bcbac2',
}

return palette[vim.o.background or 'dark']

function fish_greeting
    if not type -q tput
        or test (tput lines) -lt 40
        or test (tput cols) -lt 112
        return
    end
    echo '                   '(set_color brred)'___
    ___======____='(set_color red)'-'(set_color bryellow)'-'(set_color red)'-='(set_color brred)')
  /T            \_'(set_color bryellow)'--='(set_color red)'=='(set_color brred)')    '(set_color red)(whoami)'@'(hostname)'
  [ \ '(set_color red)'('(set_color bryellow)'0'(set_color red)')   '(set_color brred)'\~    \_'(set_color bryellow)'-='(set_color red)'='(set_color brred)')'(set_color yellow)'    Uptime: '(set_color white)(string match -rg '.*up\s+([^,]*), .*' (uptime))(set_color red)'
   \      / )J'(set_color red)'~~    \\'(set_color bryellow)'-='(set_color brred)')    Terminal: '(set_color white)(echo $TERM)(set_color red)'
    \\\\___/  )JJ'(set_color red)'~'(set_color bryellow)'~~   '(set_color brred)'\)     '(set_color yellow)'Version: '(set_color white)(echo $FISH_VERSION)(set_color red)'
     \_____/JJJ'(set_color red)'~~'(set_color bryellow)'~~    '(set_color brred)'\\
     '(set_color red)'/ '(set_color bryellow)'\  '(set_color bryellow)', \\'(set_color brred)'J'(set_color red)'~~~'(set_color bryellow)'~~     '(set_color red)'\\
    (-'(set_color bryellow)'\)'(set_color brred)'\='(set_color red)'|'(set_color bryellow)'\\\\\\'(set_color red)'~~'(set_color bryellow)'~~       '(set_color red)'L_'(set_color bryellow)'_
    '(set_color red)'('(set_color brred)'\\'(set_color red)'\\)  ('(set_color bryellow)'\\'(set_color red)'\\\)'(set_color brred)'_           '(set_color bryellow)'\=='(set_color red)'__
     '(set_color brred)'\V    '(set_color red)'\\\\'(set_color brred)'\) =='(set_color red)'=_____   '(set_color bryellow)'\\\\\\\\'(set_color red)'\\\\
            '(set_color brred)'\V)     \_) '(set_color red)'\\\\'(set_color bryellow)'\\\\JJ\\'(set_color red)'J\)
                        '(set_color brred)'/'(set_color red)'J'(set_color bryellow)'\\'(set_color red)'J'(set_color brred)'T\\'(set_color red)'JJJ'(set_color brred)'J)
                        (J'(set_color red)'JJ'(set_color brred)'| \UUU)
                         (UU)'(set_color normal)
end

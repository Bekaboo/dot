-- KaTeX uses double dollars ('$$') for (display) math mode, however
-- enclosing some LaTeX environments in double dollars will cause
-- 'Error Nesting' exception because these LaTeX environments already
-- put us in math mode. This filter will remove the double dollars
-- enclosing these LaTeX environments so that we can fluently compile
-- markdown to PDF while at the same time previewing markdown with
-- KaTeX without the need to change the math equation formats manually.

-- LaTeX math environments that need not
-- to be enclosed by double dollars ('$$')
local math_env = {
    [[\begin{align[*]?}]],
    [[\begin{alignat[*]?}]],
    [[\begin{equation[*]?}]],
    [[\end{align[*]?}]],
    [[\end{alignat[*]?}]],
    [[\end{equation[*]?}]],
}

-- Determine whether a string contains some substrings
local function substr(str, patterns)
    for _, pattern in ipairs(patterns) do
        if str:find(pattern) then
            return true
        end
    end
    return false
end

-- Given a pandoc math element, substitute it with its text (in LaTeX format)
-- if it is already enclosed by a math environment defined above.
local function math_filter(elem)
    if substr(elem.text, math_env) then
        return pandoc.RawInline('tex', elem.text)
    end
    return nil
end

local function str_filter(elem)
    if
        elem.text == '[[TOC]]' -- Remove Markdown TOC
        or elem.text:find(':%S+:') -- Remove emoji
    then
        return {}
    end
    return nil
end

return {
    { Math = math_filter },
    { Str = str_filter },
}

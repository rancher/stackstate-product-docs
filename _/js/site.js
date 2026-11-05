!function(){"use strict";var o=/^sect(\d)$/,i=document.querySelector(".nav-container"),a=document.querySelector(".nav-toggle");a.addEventListener("click",function(e){if(a.classList.contains("is-active"))return u(e);v(e);var t=document.documentElement;t.classList.add("is-clipped--nav"),a.classList.add("is-active"),i.classList.add("is-active");var n=c.getBoundingClientRect(),e=window.innerHeight-Math.round(n.top);Math.round(n.height)!==e&&(c.style.height=e+"px");t.addEventListener("click",u)}),i.addEventListener("click",v);var e,c,r,s,l=i.querySelector("[data-panel=menu]");function t(){var e,t,n=window.location.hash;if(n&&(n.indexOf("%")&&(n=decodeURIComponent(n)),!(e=l.querySelector('.nav-link[href="'+n+'"]')))){n=document.getElementById(n.slice(1));if(n)for(var i=n,a=document.querySelector("article.doc");(i=i.parentNode)&&i!==a;){var c=i.id;if((c=!c&&(c=o.test(i.className))?(i.firstElementChild||{}).id:c)&&(e=l.querySelector('.nav-link[href="#'+c+'"]')))break}}if(e)t=e.parentNode;else{if(!s)return;e=(t=s).querySelector(".nav-link")}t!==r&&(h(l,".nav-item.is-active").forEach(function(e){e.classList.remove("is-active","is-current-path","is-current-page")}),t.classList.add("is-current-page"),d(r=t),p(l,e))}function d(e){for(var t,n=e.parentNode;!(t=n.classList).contains("nav-menu");)"LI"===n.tagName&&t.contains("nav-item")&&t.add("is-active","is-current-path"),n=n.parentNode;e.classList.add("is-active")}function n(){var e,t,n,i;this.classList.toggle("is-active")&&(e=parseFloat(window.getComputedStyle(this).marginTop),t=this.getBoundingClientRect(),n=l.getBoundingClientRect(),0<(i=(t.bottom-n.top-n.height+e).toFixed())&&(l.scrollTop+=Math.min((t.top-n.top-e).toFixed(),i)))}function u(e){v(e);e=document.documentElement;e.classList.remove("is-clipped--nav"),a.classList.remove("is-active"),i.classList.remove("is-active"),e.removeEventListener("click",u)}function v(e){e.stopPropagation()}function p(e,t){var n=e.getBoundingClientRect(),i=n.height,a=window.getComputedStyle(c);"sticky"===a.position&&(i-=n.top-parseFloat(a.top)),e.scrollTop=Math.max(0,.5*(t.getBoundingClientRect().height-i)+t.offsetTop)}function h(e,t){return[].slice.call(e.querySelectorAll(t))}l&&(e=i.querySelector("[data-panel=explore]"),c=i.querySelector(".nav"),r=l.querySelector(".is-current-page"),(s=r)?(d(r),p(l,r.querySelector(".nav-link"))):l.scrollTop=0,h(l,".nav-item-toggle").forEach(function(e){var t=e.parentElement;e.addEventListener("click",n.bind(t));e=function(e,t){e=e.nextElementSibling;return(!e||!t||e[e.matches?"matches":"msMatchesSelector"](t))&&e}(e,".nav-text");e&&(e.style.cursor="pointer",e.addEventListener("click",n.bind(t)))}),e&&e.querySelector(".context").addEventListener("click",function(){h(c,"[data-panel]").forEach(function(e){e.classList.toggle("is-active")})}),l.addEventListener("mousedown",function(e){1<e.detail&&e.preventDefault()}),l.querySelector('.nav-link[href^="#"]')&&(window.location.hash&&t(),window.addEventListener("hashchange",t)))}();
!function(){"use strict";var e=document.querySelector("aside.toc.sidebar");if(e){if(document.querySelector("body.-toc"))return e.parentNode.removeChild(e);var t=parseInt(e.dataset.levels||2,10);if(!(t<0)){for(var o="article.doc",d=document.querySelector(o),n=[],i=0;i<=t;i++){var r=[o];if(i){for(var a=1;a<=i;a++)r.push((2===a?".sectionbody>":"")+".sect"+a);r.push("h"+(i+1)+"[id]")}else r.push("h1[id].sect0");n.push(r.join(">"))}var c,s,l,u=(c=n.join(","),s=d.parentNode,[].slice.call((s||document).querySelectorAll(c)));if(!u.length)return e.parentNode.removeChild(e);var f={},m=u.reduce(function(e,t){var o=document.createElement("a");o.textContent=t.textContent,f[o.href="#"+t.id]=o;var n=document.createElement("li");return n.dataset.level=parseInt(t.nodeName.slice(1),10)-1,n.appendChild(o),e.appendChild(n),e},document.createElement("ul")),p=e.querySelector(".toc-menu");p||((p=document.createElement("div")).className="toc-menu");var v=document.createElement("h3");v.textContent=e.dataset.title||"Contents",p.appendChild(v),p.appendChild(m);e=!document.getElementById("toc")&&d.querySelector("h1.page ~ :not(.is-before-toc)");e&&((v=document.createElement("aside")).className="toc embedded",v.appendChild(p.cloneNode(!0)),e.parentNode.insertBefore(v,e)),window.addEventListener("load",function(){h(),window.addEventListener("scroll",h)})}}function h(){var t,e=window.pageYOffset,o=1.15*g(document.documentElement,"fontSize"),n=d.offsetTop;if(e&&window.innerHeight+e+2>=document.documentElement.scrollHeight){l=Array.isArray(l)?l:Array(l||0);var i=[],r=u.length-1;return u.forEach(function(e,t){var o="#"+e.id;t===r||e.getBoundingClientRect().top+g(e,"paddingTop")>n?(i.push(o),l.indexOf(o)<0&&f[o].classList.add("is-active")):~l.indexOf(o)&&f[l.shift()].classList.remove("is-active")}),m.scrollTop=m.scrollHeight-m.offsetHeight,void(l=1<i.length?i:i[0])}Array.isArray(l)&&(l.forEach(function(e){f[e].classList.remove("is-active")}),l=void 0),u.some(function(e){return e.getBoundingClientRect().top+g(e,"paddingTop")-o>n||void(t="#"+e.id)}),t?t!==l&&(l&&f[l].classList.remove("is-active"),(e=f[t]).classList.add("is-active"),m.scrollHeight>m.offsetHeight&&(m.scrollTop=Math.max(0,e.offsetTop+e.offsetHeight-m.offsetHeight)),l=t):l&&(f[l].classList.remove("is-active"),l=void 0)}function g(e,t){return parseFloat(window.getComputedStyle(e)[t])}}();
!function(){"use strict";var o=document.querySelector("article.doc"),t=document.querySelector(".toolbar");function i(e){return e&&(~e.indexOf("%")?decodeURIComponent(e):e).slice(1)}function r(e){if(e){if(e.altKey||e.ctrlKey)return;window.location.hash="#"+this.id,e.preventDefault()}window.scrollTo(0,function e(t,n){return o.contains(t)?e(t.offsetParent,t.offsetTop+n):n}(this,0)-t.getBoundingClientRect().bottom)}window.addEventListener("load",function e(t){var n,o;(n=i(window.location.hash))&&(o=document.getElementById(n))&&(r.bind(o)(),setTimeout(r.bind(o),0)),window.removeEventListener("load",e)}),Array.prototype.slice.call(document.querySelectorAll('a[href^="#"]')).forEach(function(e){var t,n;(t=i(e.hash))&&(n=document.getElementById(t))&&e.addEventListener("click",r.bind(n))})}();
!function(){"use strict";var t,e=document.querySelector(".page-versions .version-menu-toggle");e&&(t=document.querySelector(".page-versions"),e.addEventListener("click",function(e){t.classList.toggle("is-active"),e.stopPropagation()}),document.documentElement.addEventListener("click",function(){t.classList.remove("is-active")}))}();
!function(){"use strict";var t=document.querySelector(".navbar-burger");t&&t.addEventListener("click",function(t){t.stopPropagation(),document.documentElement.classList.toggle("is-clipped--navbar"),this.classList.toggle("is-active");var e=document.getElementById(this.dataset.target);e.classList.toggle("is-active")&&(e.style.maxHeight="",t=window.innerHeight-Math.round(e.getBoundingClientRect().top),parseInt(window.getComputedStyle(e).maxHeight,10)!==t&&(e.style.maxHeight=t+"px"))}.bind(t))}();

/* Rancher patch: replaces the default UI copy-to-clipboard module so that
   console blocks can use "$ ", "# " (root) or "> " prompts, "> " lines can
   continue a command, and heredoc bodies are copied. Only real prompts are
   unselectable with the mouse. The rest of this file is the unmodified site.js
   from default-ui/ui-bundle.zip. */
!(function () {
  'use strict'

  var TRAILING_SPACE_RX = / +$/gm
  // <<EOF, <<-EOF, <<'EOF', <<"EOF", but not <<< (here-string) or $((1<<2))
  var HEREDOC_RX = /(?:^|[^<])<<(-?) *(['"]?)([A-Za-z_][\w.-]*)\2/g

  var config = (document.getElementById('site-script') || { dataset: {} }).dataset

  // Return the commands in a console block without prompts or output.
  // The prompt is taken from the first line, so "# " lines are comments or
  // output in a "$ " block, and commands in a "# " block. In a "$ " or "# "
  // block, "> " lines after a command continue it (multi-line strings).
  // A trailing "\" joins the next line, without any "> " prompt.
  // Heredoc bodies are copied up to the delimiter line in any block. The body
  // lines can be written with or without a "> " prompt, as decided by the
  // first body line.
  // If promptLines is an array, the index of each line with a prompt is added.
  function extractCommands (text, promptLines) {
    var prompt = text.slice(0, 2)
    var cmds = []
    var cmd
    var multiline = false
    var heredocs = []
    var bodyPrompt

    function addHeredocs (part) {
      var match
      HEREDOC_RX.lastIndex = 0
      while ((match = HEREDOC_RX.exec(part))) heredocs.push({ word: match[3], tabs: match[1] === '-' })
      bodyPrompt = undefined
    }

    function markPrompt (i) {
      if (promptLines) promptLines.push(i)
    }

    text.split('\n').forEach(function (line, i) {
      if (heredocs.length) {
        if (bodyPrompt == null) bodyPrompt = /^>( |$)/.test(line)
        if (bodyPrompt && /^>( |$)/.test(line)) {
          markPrompt(i)
          line = line.replace(/^> ?/, '')
        }
        cmd += '\n' + line
        multiline = true
        if ((heredocs[0].tabs ? line.replace(/^\t+/, '') : line) === heredocs[0].word) {
          heredocs.shift()
          bodyPrompt = undefined
        }
      } else if (line.startsWith(prompt)) {
        if (cmd != null) cmds.push(cmd)
        markPrompt(i)
        cmd = line.slice(2)
        addHeredocs(cmd)
      } else if (cmd != null && /\\$/.test(cmd)) {
        if (/^> /.test(line)) markPrompt(i)
        var rest = line.replace(/^> /, '')
        var sep = / \\$/.test(cmd) || rest.charAt(0) === ' ' ? ' ' : ''
        cmd = cmd.replace(/ *\\$/, '') + sep + rest.replace(/^ +/, '')
        addHeredocs(rest)
      } else if (cmd != null && prompt !== '> ' && /^>( |$)/.test(line)) {
        // a blank continuation line is just ">" once trailing spaces are gone
        markPrompt(i)
        cmd += '\n' + line.slice(2)
        multiline = true
        addHeredocs(line)
      } else {
        if (cmd != null) cmds.push(cmd)
        cmd = undefined
      }
    })
    if (cmd != null) cmds.push(cmd)
    return cmds.join(multiline ? '\n' : ' && ')
  }

  // A block that starts with "$ " or "> " has prompts. A block that starts
  // with "# " has root prompts only if all lines have a "# " or "> " prompt.
  // Otherwise the "# " line is a comment, for example in a script, and the
  // block is copied as shown.
  function hasPrompt (text) {
    if (/^[$>] /.test(text)) return true
    return /^# /.test(text) && text.split('\n').every(function (line) {
      return !line.trim() || /^(# |>( |$))/.test(line)
    })
  }

  ;[].slice.call(document.querySelectorAll('.doc pre.highlight, .doc .literalblock pre')).forEach(function (pre) {
    var code, language, lang, copy, toast, toolbox
    if (pre.classList.contains('highlight')) {
      code = pre.querySelector('code')
      if ((language = code.dataset.lang) && language !== 'console') {
        ;(lang = document.createElement('span')).className = 'source-lang'
        lang.appendChild(document.createTextNode(language))
      }
    } else if (pre.innerText.startsWith('$ ')) {
      var block = pre.parentNode.parentNode
      block.classList.remove('literalblock')
      block.classList.add('listingblock')
      pre.classList.add('highlightjs', 'highlight')
      ;(code = document.createElement('code')).className = 'language-console hljs'
      code.dataset.lang = 'console'
      code.appendChild(pre.firstChild)
      pre.appendChild(code)
    } else {
      return
    }
    ;(toolbox = document.createElement('div')).className = 'source-toolbox'
    if (lang) toolbox.appendChild(lang)
    if (window.navigator.clipboard) {
      ;(copy = document.createElement('button')).className = 'copy-button'
      copy.setAttribute('title', 'Copy to clipboard')
      if (config.svgAs === 'svg') {
        var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
        svg.setAttribute('class', 'copy-icon')
        var use = document.createElementNS('http://www.w3.org/2000/svg', 'use')
        use.setAttribute('href', window.uiRootPath + '/img/octicons-16.svg#icon-clippy')
        svg.appendChild(use)
        copy.appendChild(svg)
      } else {
        var img = document.createElement('img')
        img.src = window.uiRootPath + '/img/octicons-16.svg#view-clippy'
        img.alt = 'copy icon'
        img.className = 'copy-icon'
        copy.appendChild(img)
      }
      ;(toast = document.createElement('span')).className = 'copy-toast'
      toast.appendChild(document.createTextNode('Copied!'))
      copy.appendChild(toast)
      toolbox.appendChild(copy)
    }
    pre.appendChild(toolbox)
    if (copy) copy.addEventListener('click', writeToClipboard.bind(copy, code))
  })

  // highlight.js marks each "$", "#" or ">" at the start of a line in a console
  // block as a prompt (hljs-meta), and the bundle CSS makes it unselectable.
  // Keep this only for the prompts that the copy button removes. Then a comment
  // such as "# rm ..." keeps its "#" when a user selects it with the mouse.
  // highlight.js loads async, so do this on the load event.
  function fixPromptSelection () {
    ;[].slice.call(document.querySelectorAll('.doc pre.highlight code.language-console')).forEach(function (code) {
      var text = code.innerText.replace(TRAILING_SPACE_RX, '')
      var promptLines = []
      if (hasPrompt(text)) extractCommands(text, promptLines)
      ;[].slice.call(code.querySelectorAll('.hljs-meta')).forEach(function (meta) {
        var range = document.createRange()
        range.setStart(code, 0)
        range.setEndBefore(meta)
        // the meta text can start with the newline of a blank line before it
        var line = range.toString().split('\n').length - 1 + meta.textContent.match(/^\n*/)[0].length
        if (promptLines.indexOf(line) < 0) meta.classList.remove('hljs-meta')
      })
    })
  }

  window.addEventListener('load', fixPromptSelection)

  function writeToClipboard (code) {
    var text = code.innerText.replace(TRAILING_SPACE_RX, '')
    if (code.dataset.lang === 'console' && hasPrompt(text)) text = extractCommands(text)
    window.navigator.clipboard.writeText(text).then(
      function () {
        this.classList.add('clicked')
        this.offsetHeight // eslint-disable-line no-unused-expressions
        this.classList.remove('clicked')
      }.bind(this),
      function () {}
    )
  }
})()

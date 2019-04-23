/**************************************************************
 * Templates, -arguments and wikilinks
 **************************************************************/

/*
 * Precedence: template arguments win over templates. See
 * http://www.mediawiki.org/wiki/Preprocessor_ABNF#Ideal_precedence
 * 4: {{{{·}}}} → {·{{{·}}}·}
 * 5: {{{{{·}}}}} → {{·{{{·}}}·}}
 * 6: {{{{{{·}}}}}} → {{{·{{{·}}}·}}}
 * 7: {{{{{{{·}}}}}}} → {·{{{·{{{·}}}·}}}·}
 * This is only if close has > 3 braces; otherwise we just match open
 * and close as we find them.
 */
tplarg_or_template
  = &'{{'
    templatedepth:<templatedepth>
    &{
      // Refuse to recurse beyond `maxDepth` levels. Default in the PHP parser
      // is $wgMaxTemplateDepth = 40; This is to prevent crashing from
      // buggy wikitext with lots of unclosed template calls, as in
      // eswiki/Usuario:C%C3%A1rdenas/PRUEBAS?oldid=651094
      return templatedepth + 1 < env.conf.maxDepth;
    }
    t:tplarg_or_template_guarded<templatedepth++> { return t; }

tplarg_or_template_guarded
  = &('{{' &('{{{'+ !'{') tplarg) a:(template/broken_template) { return a; }
    / a:$('{' &('{{{'+ !'{'))? b:tplarg { return [a].concat(b); }
    / a:$('{' &('{{' !'{'))? b:template { return [a].concat(b); }
    / a:broken_template { return a; }

tplarg_or_template_or_bust "tplarg_or_template_or_bust"
    = r:(tplarg_or_template / .)+ { return tu.flattenIfArray(r); }

template
  = template_preproc<&preproc="}}">

// The PHP preprocessor maintains a single stack of "closing token we
// are currently looking for", with no backtracking.  This means that
// once you see `[[ {{` you are looking only for `}}` -- if that template
// turns out to be broken you will never pop the `}}` and there is no way
// to close the `[[`.  Since the PEG tokenizer in Parsoid uses backtracking
// and parses in a single pass (instead of PHP's split preprocessor/parser)
// we have to be a little more careful when we emulate this behavior.
// If we use a rule like:
//   template = "{{" tplname tplargs* "}}"?
// Then we end up having to reinterpret `tplname tplargs*` as a tlb if it
// turns out we never find the `}}`, which involves a lot of tedious gluing
// tokens back together with fingers crossed we haven't discarded any
// significant newlines/whitespace/etc.  An alternative would be a rule like:
//   broken_template = "{{" tlb
// but again, `template` is used in many different contexts; `tlb` isn't
// necessarily the right one to recursively invoke.  Instead we get the
// broken template off of the PEGjs production stack by returning immediately
// after `{{`, but we set the "preproc" reference parameter to false (the
// reference parameter feature having been introduced for this sole purpose)
// to indicate to the parent rule that we're "still in" the {{ context and
// shouldn't ever inlineBreak for any closing tokens above this one.  For
// example:
//   [[Foo{{Bar]]
// This will match as:
//   wikilink->text,template->text             --> FAILS looking for }}
//     backtracks, popping "bracket_bracket" and "brace_brace" off preproc stack
//   wikilink->text,broken_template,text       --> FAILS looking for ]]
//     backtracks, popping "bracket_bracket" and false off preproc stack
//   broken_wikilink,text,broken_template,text --> OK
//     with [false, false] left on the preproc stack

broken_template
  = preproc:<&preproc>
    t:"{{" {
        preproc.set(null);
        return t;
    }

template_preproc
  = "{{" nl_comment_space*
    target:template_param_value
    params:(nl_comment_space* "|"
                r:( p0:("" { return endOffset(); })
                    v:nl_comment_space*
                    p:("" { return endOffset(); })
                    &("|" / "}}")
                    { return new KV('', tu.flattenIfArray(v), [p0, p0, p0, p]); } // empty argument
                    / template_param
                  ) { return r; }
            )*
    nl_comment_space*
    inline_breaks "}}" {
      // Insert target as first positional attribute, so that it can be
      // generically expanded. The TemplateHandler then needs to shift it out
      // again.
      params.unshift(new KV(tu.flattenIfArray(target.tokens), '', target.srcOffsets));
      var obj = new SelfclosingTagTk('template', params, { tsr: tsrOffsets(), src: text() });
      return obj;
    } / $('{{' space_or_newline* '}}')

tplarg
  = tplarg_preproc<&preproc="}}">

tplarg_preproc
  = "{{{"
    p:("" { return endOffset(); })
    target:template_param_value?
    params:(nl_comment_space* "|"
                r:( p0:("" { return endOffset(); })
                    v:nl_comment_space*
                    p1:("" { return endOffset(); })
                    &("|" / "}}}")
                    { return { tokens: v, srcOffsets: [p0, p1] }; }  // empty argument
                    / template_param_value
                  ) { return r; }
            )*
    nl_comment_space*
    inline_breaks "}}}" {
      params = params.map(function(o) {
        var s = o.srcOffsets;
        return new KV('', tu.flattenIfArray(o.tokens), [s[0], s[0], s[0], s[1]]);
      });
      if (target === null) { target = { tokens: '', srcOffsets: [p, p, p, p] }; }
      // Insert target as first positional attribute, so that it can be
      // generically expanded. The TemplateHandler then needs to shift it out
      // again.
      params.unshift(new KV(tu.flattenIfArray(target.tokens), '', target.srcOffsets));
      var obj = new SelfclosingTagTk('templatearg', params, { tsr: tsrOffsets(), src: text() });
      return obj;
    }

template_param
  = name:template_param_name
    val:(
        kEndPos:("" { return endOffset(); })
        optionalSpaceToken
        "="
        vStartPos:("" { return endOffset(); })
        optionalSpaceToken
        tpv:template_param_value? {
            return { kEndPos: kEndPos, vStartPos: vStartPos, value: (tpv && tpv.tokens) || [] };
        }
    )? {
      if (val !== null) {
          if (val.value !== null) {
            return new KV(name, tu.flattenIfArray(val.value), [startOffset(), val.kEndPos, val.vStartPos, endOffset()]);
          } else {
            return new KV(tu.flattenIfArray(name), '', [startOffset(), val.kEndPos, val.vStartPos, endOffset()]);
          }
      } else {
        return new KV('', tu.flattenIfArray(name), [startOffset(), startOffset(), startOffset(), endOffset()]);
      }
    }
  // empty parameter
  / & [|}] {
    return new KV('', '', [startOffset(), startOffset(), startOffset(), endOffset()]);
  }

template_param_name
  = tpt:(template_param_text<equal> / &'=' { return ''; })
    {
        return tpt;
    }

template_param_value
  = tpt:template_param_text<equal=false>
    {
        return { tokens: tpt, srcOffsets: tsrOffsets() };
    }

template_param_text
  = il:(nested_block<table=false, extlink=false, templateArg=true, tableCellArg=false> / newlineToken)+ {
        // il is guaranteed to be an array -- so, tu.flattenIfArray will
        // always return an array
        var r = tu.flattenIfArray(il);
        if (r.length === 1 && r[0].constructor === String) {
            r = r[0];
        }
        return r;
    }

//// Language converter block markup of language variants: -{ ... }-

// Note that "rightmost opening" precedence rule (see
// https://www.mediawiki.org/wiki/Preprocessor_ABNF ) means
// that neither -{{ nor -{{{ are parsed as a -{ token, although
// -{{{{ is (since {{{ has precedence over {{).

lang_variant_or_tpl
  = &('-{' &('{{{'+ !'{') tplarg) a:lang_variant { return a; }
  / a:$('-' &('{{{'+ !'{')) b:tplarg { return [a].concat(b); }
  / a:$('-' &('{{' '{{{'* !'{')) b:template { return [a].concat(b); }
  / &'-{' a:lang_variant { return a; }

broken_lang_variant
  = r:"-{"
    preproc:<&preproc>
    {
        preproc.set(null);
        return r;
    }

lang_variant
  = lang_variant_preproc<&preproc="}-">
  / broken_lang_variant

lang_variant_preproc
  = lv0:("-{" { return startOffset(); })
    f:(
       &{ return env.langConverterEnabled(); }
       ff:opt_lang_variant_flags {
         // Avoid mutating cached expression results
         ff = Util.clone(ff, true);
         // if flags contains 'R', then don't treat ; or : specially inside.
         if (ff.flags) {
           ff.raw = ff.flags.has('R') || ff.flags.has('N');
         } else if (ff.variants) {
           ff.raw = true;
         }
         return ff;
       } /
       &{ return !env.langConverterEnabled(); }
       "" {
         // if language converter not enabled, don't try to parse inside.
         return { raw: true };
       }
    )
    ts:(
      &{ return f.raw; } lv:lang_variant_text { return [{ text: lv }]; }
      /
      &{ return !f.raw; } lv:lang_variant_option_list { return lv; }
    )
    inline_breaks
    lv1:("}-" { return endOffset(); }) {

      if (!env.langConverterEnabled()) {
        return [ "-{", ts[0].text.tokens, "}-" ];
      }
      var lvsrc = input.substring(lv0, lv1);
      var attribs = [];

      // Do a deep clone since we may be destructively modifying
      // (the `t[fld] = name;` below) the result of a cached expression
      ts = Util.clone(ts, true);

      ts.forEach(function(t) {
        // move token strings into KV attributes so that they are
        // properly expanded by early stages of the token pipeline
        ['text','from','to'].forEach(function(fld) {
          if (t[fld] === undefined) { return; }
          var name = 'mw:lv' + attribs.length;
          // Note that AttributeExpander will expect the tokens array to be
          // flattened.  We do that in lang_variant_text / lang_variant_nowiki
          attribs.push(new KV(name, t[fld].tokens, t[fld].srcOffsets));
          t[fld] = name;
        });
      });
      return [
        new SelfclosingTagTk(
          'language-variant',
           attribs,
           {
             tsr: [lv0, lv1],
             src: lvsrc,
             flags: f.flags && Array.from(f.flags).sort(),
             variants: f.variants && Array.from(f.variants).sort(),
             original: f.original,
             flagSp: f.sp,
             texts: ts,
           }),
      ];
    }

opt_lang_variant_flags
  = f:( ff:lang_variant_flags "|" { return ff; } )? {
    // Collect & separate flags and variants into a set and ordered list
    var flags = new Set();
    var variants = new Set();
    var flagList = [];
    var flagSpace = [];
    var variantList = [];
    var variantSpace = [];
    var useVariants = false;
    if (f !== null) {
      // lang_variant_flags returns arrays in reverse order.
      f.flags.reverse();
      f.sp.reverse();
      var spPtr = 0;
      f.flags.forEach(function(item) {
        if (item.flag) {
          flagSpace.push(f.sp[spPtr++]);
          flags.add(item.flag);
          flagList.push(item.flag);
          flagSpace.push(f.sp[spPtr++]);
        }
        if (item.variant) {
          variantSpace.push(f.sp[spPtr++]);
          variants.add(item.variant);
          variantList.push(item.variant);
          variantSpace.push(f.sp[spPtr++]);
        }
      });
      if (spPtr < f.sp.length) {
        // handle space after a trailing semicolon
        flagSpace.push(f.sp[spPtr]);
        variantSpace.push(f.sp[spPtr]);
      }
    }
    // Parse flags (this logic is from core/languages/ConverterRule.php
    // in the parseFlags() function)
    if (flags.size === 0 && variants.size === 0) {
      flags.add('$S');
    } else if (flags.has('R')) {
      flags = new Set(['R']); // remove other flags
    } else if (flags.has('N')) {
      flags = new Set(['N']); // remove other flags
    } else if (flags.has('-')) {
      flags = new Set(['-']); // remove other flags
    } else if (flags.has('T') && flags.size === 1) {
      flags.add('H');
    } else if (flags.has('H')) {
      // Replace A flag, and remove other flags except T and D
      var nf = new Set(['$+', 'H']);
      if (flags.has('T')) { nf.add('T'); }
      if (flags.has('D')) { nf.add('D'); }
      flags = nf;
    } else if (variants.size > 0) {
      useVariants = true;
    } else {
      if (flags.has('A')) {
        flags.add('$+');
        flags.add('$S');
      }
      if (flags.has('D')) {
        flags.delete('$S');
      }
    }
    if (useVariants) {
      return { variants: variants, original: variantList, sp: variantSpace };
    } else {
      return { flags: flags, original: flagList, sp: flagSpace };
    }
  }

lang_variant_flags
  = sp1:$(space_or_newline*) f:lang_variant_flag sp2:$(space_or_newline*)
    more:( ";" lang_variant_flags? )? {
    var r = more && more[1] ? more[1] : { sp: [], flags: [] };
    // Note that sp and flags are in reverse order, since we're using
    // right recursion and want to push instead of unshift.
    r.sp.push(sp2);
    r.sp.push(sp1);
    r.flags.push(f);
    return r;
  }
  / sp:$(space_or_newline*) {
    return { sp: [ sp ], flags: [] };
  }

lang_variant_flag
  = f:[-+A-Z]           { return { flag: f }; }
  / v:lang_variant_name { return { variant: v }; }
  / b:$(!space_or_newline !nowiki [^{}|;])+ { return { bogus: b }; /* bad flag */}

lang_variant_name // language variant name, like zh, zh-cn, etc.
  = $([a-z] [-a-z]+)
  // Escaped otherwise-unrepresentable language names
  // Primarily for supporting html2html round trips; PHP doesn't support
  // using nowikis here (yet!)
  / nowiki_text

lang_variant_option_list
  = o:lang_variant_option rest:( ";" oo:lang_variant_option { return oo; })*
    tr:( ";" $space_or_newline* )? // optional trailing semicolon
    {
      var r = [ o ].concat(rest);
      if (tr) { r.push({ semi: true, sp: tr[1] }); }
      return r;
    }
  / lvtext:lang_variant_text { return [{ text: lvtext }]; }

lang_variant_option
  = sp1:$(space_or_newline*) lang:lang_variant_name
    sp2:$(space_or_newline*) ":"
    sp3:$(space_or_newline*)
    lvtext:(lang_variant_nowiki / lang_variant_text_no_semi)
    {
      return {
        twoway: true,
        lang: lang,
        text: lvtext,
        sp: [sp1, sp2, sp3]
      };
    }
  / sp1:$(space_or_newline*)
    from:(lang_variant_nowiki / lang_variant_text_no_semi_or_arrow)
    "=>"
    sp2:$(space_or_newline*) lang:lang_variant_name
    sp3:$(space_or_newline*) ":"
    sp4:$(space_or_newline*)
    to:(lang_variant_nowiki / lang_variant_text_no_semi)
    {
      return {
        oneway: true,
        from: from,
        lang: lang,
        to: to,
        sp: [sp1, sp2, sp3, sp4]
      };
    }

// html2wt support: If a language name or conversion string can't be
// represented w/o breaking wikitext, just wrap it in a <nowiki>.
// PHP doesn't support this (yet), but Parsoid does.
lang_variant_nowiki
  = n:nowiki_text
    sp:$space_or_newline*
    {
        return { tokens: [ n ], srcOffsets: [startOffset(), endOffset() - sp.length] };
    }

lang_variant_text
  = tokens:(inlineline / "|" )*
    { return { tokens: tu.flattenStringlist(tokens), srcOffsets: [startOffset(), endOffset()] }; }

lang_variant_text_no_semi
  = lang_variant_text<semicolon>

lang_variant_text_no_semi_or_arrow
  = lang_variant_text_no_semi<arrow>

wikilink_content
  = ( pipe startPos:("" { return endOffset(); }) lt:link_text? {
        var maybeContent = new KV('mw:maybeContent', lt, [startPos, endOffset()]);
        maybeContent.vsrc = input.substring(startPos, endOffset());
        return maybeContent;
  } )*

wikilink
  = wikilink_preproc<&preproc="]]">
    / broken_wikilink

// `broken-link` (see [[:mw:Preprocessor_ABNF]]), but careful because the
// second bracket could start an extlink.  Set preproc to false as a reference
// parameter in the parent since we haven't seen a double-close bracket.
// (See full explanation above broken_template production.)
broken_wikilink
  = &"[["
    preproc:<&preproc>
    &{ preproc.set(null); return true; }
    a:("[" (extlink / "[")) {
        return a;
    }

wikilink_preproc
  = "[["
    target:wikilink_preprocessor_text?
    tpos:("" { return endOffset(); })
    lcs:wikilink_content
    inline_breaks "]]"
  {
      var pipeTrick = (lcs.length === 1 && lcs[0].v === null);
      var textTokens = [];
      if (target === null || pipeTrick) {
        textTokens.push("[[");
        if (target) {
          textTokens.push(target);
        }
        lcs.forEach(function(a) {
          // a is a mw:maybeContent attribute
          textTokens.push("|");
          if (a.v !== null) { textTokens.push(a.v); }
        });
        textTokens.push("]]");
        return textTokens;
      }
      var obj = new SelfclosingTagTk('wikilink');
      var hrefKV = new KV('href', target);
      hrefKV.vsrc = input.substring(startOffset() + 2, tpos);
      // XXX: Point to object with path, revision and input information
      // obj.source = input;
      obj.attribs.push(hrefKV);
      obj.attribs = obj.attribs.concat(lcs);
      obj.dataAttribs = {
          tsr: tsrOffsets(),
          src: text(),
      };
      return [obj];
  }

// Tables are allowed inside image captions.
// Suppress the equal flag temporarily in this rule to consume the '=' here.
link_text = link_text_parameterized<equal = false, linkdesc = true>

link_text_parameterized
  = c:(  // This group is similar to "block_line" but "list_item"
         // is omitted since `doBlockLevels` happens after
         // `replaceInternalLinks2`, where newlines are stripped.
         (sol (heading / hr / full_table_in_link_caption))
       / urltext
       / (!inline_breaks
          r:( inline_element / '[' text_char+ ']' $(&(!']' / ']]')) / . ) { return r; }
         )
    )+ {
      return tu.flattenStringlist(c);
    }

/* Generic quote rule for italic and bold, further processed in a token
 * stream transformation in doQuotes. Relies on NlTk tokens being emitted
 * for each line of text to balance quotes per line.
 *
 * We are not using a simple pair rule here as we need to support mis-nested
 * bolds/italics and MediaWiki's special heuristics for apostrophes, which are
 * all not context free. */
quote = quotes:$("''" "'"*) {
    // sequences of four or more than five quotes are assumed to start
    // with some number of plain-text apostrophes.
    var plainticks = 0;
    var result = [];
    if (quotes.length === 4) {
        plainticks = 1;
    } else if (quotes.length > 5) {
        plainticks = quotes.length - 5;
    }
    if (plainticks > 0) {
        result.push(quotes.substring(0, plainticks));
    }
    // mw-quote token Will be consumed in token transforms
    var tsr = tsrOffsets();
    tsr[0] += plainticks;
    var mwq = new SelfclosingTagTk('mw-quote', [new KV('value', quotes.substring(plainticks))], { tsr: tsr });
    if (quotes.length > 2) {
        mwq.addAttribute('preceding-2chars', input.substring(tsr[0] - 2, tsr[0]));
    }
    result.push(mwq);
    return result;
}

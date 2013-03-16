do ->

    CELL_HTML = _.template """
      <input class="list-chooser" type="checkbox" style="display: none">
      <a class="im-cell-link" href="<%= url %>">
        <% if (url != null && !url.match(host)) { %>
          <% if (icon) { %>
            <img src="<%= icon %>" class="im-external-link"></img>
          <% } else { %>
            <i class="icon-globe"></i>
          <% } %>
        <% } %>
        <% if (value == null) { %>
          <span class="null-value">&nbsp;</span>
        <% } else { %>
          <span class="im-displayed-value">
            <%- value %>
          </span>
        <% } %>
      </a>
      <% if (field == 'url' && value != url) { %>
          <a class="im-cell-link external" href="<%= value %>"><i class="icon-globe"></i>link</a>
      <% } %>
    """


    class SubTable extends Backbone.View
        tagName: "td"
        className: "im-result-subtable"

        initialize: ->
            @query = @options.query
            @cellify = @options.cellify
            @path = @options.node
            subtable = @options.subtable
            @rows = subtable.rows
            @view = subtable.view
            @column = @query.getPathInfo(subtable.column)
            @query.on 'expand:subtables', (path) =>
                if path.toString() is @column.toString()
                    @$('.im-subtable').slideDown()
            @query.on 'collapse:subtables', (path) =>
                if path.toString() is @column.toString()
                    @$('.im-subtable').slideUp()

        getSummaryText: () ->
            if @column.isCollection()
                """#{ @rows.length } #{ @column.getType().name }s"""
            else
                # Single collapsed reference.
                if @rows.length is 0
                    # find the outer join:
                    level = if @query.isOuterJoined(@view[0])
                        @query.getPathInfo(@query.getOuterJoin(@view[0]))
                    else
                        @column
                    """No #{ level.getType().name }"""
                else
                    """#{@rows[0][0].value} (#{@rows[0][1 ..].map((c) -> c.value).join(', ')})"""

        render: () ->
            icon = if @rows.length > 0 then '<i class=icon-table></i>' else '<i class=icon-non-existent></i>'
            summary = $ """<span>#{ icon }&nbsp;#{ @getSummaryText() }</span>"""
            summary.addClass('im-subtable-summary').appendTo @$el
            t = $ '<table><thead><tr></tr></thead><tbody></tbody></table>'
            colRoot = @column.getType().name
            colStr = @column.toString()
            if @rows.length > 0
                # Prefer column to view as it is reliable.
                columns = @rows[0].map (cell) -> cell.column
                for v in columns then do (v) =>
                    th = $ """<th>
                        <i class="#{intermine.css.headerIconRemove}"></i>
                        <span></span>
                    </th>"""
                    th.find('i').click (e) => @query.removeFromSelect v
                    path = @query.getPathInfo(v)
                    @column.getDisplayName (colName) =>
                        span = th.find('span')
                        if intermine.results.shouldFormat(path)
                            path = path.getParent()
                        path.getDisplayName (pathName) ->
                            if pathName.match(colName)
                                span.text pathName.replace(colName, '').replace(/^\s*>?\s*/, '')
                            else
                                span.text pathName.replace(/^[^>]*\s*>\s*/, '')
                    t.children('thead').children('tr').append th
                appendRow = (t, row) =>
                    tr = $ '<tr>'
                    w = @$el.width() / @view.length
                    for cell in row then do (tr, cell) =>
                      view = @cellify cell
                      if intermine.results.shouldFormat view.path
                        view.formatter = intermine.results.getFormatter view.path
                      else
                      tr.append view.el
                      view.render().setWidth w
                    t.children('tbody').append tr
                    null

                if @column.isCollection()
                    appendRow(t, row) for row in @rows
                else
                    appendRow(t, @rows[0]) # Odd hack to fix multiple repeated rows.


            t.addClass 'im-subtable table table-condensed table-striped'

            @$el.append t

            summary.css(cursor: 'pointer').click (e) =>
                e.stopPropagation()
                if t.is(':visible')
                    @query.trigger 'subtable:collapsed', @column
                else
                    @query.trigger 'subtable:expanded', @column
                t.slideToggle()

            this

        getUnits: () ->
            if @rows.length = 0
                @view.length
            else
                _.reduce(@rows[0], ((a, item) -> a + if item.view? then item.view.length else 1), 0)

        setWidth: (w) ->
            # @$el.css width: (w * @view.length) + "px"
            # @$('.im-cell-link').css "max-width": ((w * @view.length) - 5) + "px"
            this

    class Cell extends Backbone.View
        tagName: "td"
        className: "im-result-field"

        getUnits: () -> 1

        formatter: (model) ->
          if model.get(@options.field)?
            model.escape @options.field
          else
            """<span class="null-value">&nbsp;</span>"""

        events:
            'click': 'activateChooser'

        initialize: ->
            @model.on 'change', @selectingStateChange, @
            @model.on 'change', @updateValue, @

            @listenToQuery @options.query

            field = @options.field
            path = @path = @options.node.append field
            @$el.addClass 'im-type-' + path.getType().toLowerCase()

        listenToQuery: (q) ->
          q.on "start:list-creation", =>
            @model.set 'is:selecting': true
          q.on "stop:list-creation", =>
            @model.set 'is:selecting': false, 'is:selected': false
          q.on 'showing:preview', (el) => # Close ours if another is being opened.
            @cellPreview?.hide() unless el is @el

          q.on "start:highlight:node", (node) =>
            if @options.node?.toPathString() is node.toPathString()
              @$el.addClass "im-highlight"
          q.on "stop:highlight", => @$el.removeClass "im-highlight"

          q.on "replaced:by", (replacement) => @listenToQuery replacement
      
        getPopoverContent: =>
          return @model.cachedPopover if @model.cachedPopover?

          type = @model.get 'obj:type'
          id = @model.get 'id'

          popover = new intermine.table.cell.Preview
            service: @options.query.service
            schema: @options.query.model
            model: {type, id}

          content = popover.el

          popover.on 'ready', => @cellPreview.reposition()
          popover.render()

          @model.cachedPopover = content

        getPopoverPlacement: (popover) =>
          table = @$el.closest ".im-table-container"
          {left} = @$el.offset()

          limits = table.offset()
          _.extend limits,
            right: limits.left + table.width()
            bottom: limits.top + table.height()

          w = @$el.width()
          h = @$el.height()
          elPos = @$el.offset()

          pw = $(popover).outerWidth()
          ph = $(popover)[0].offsetHeight

          fitsOnRight = left + w + pw <= limits.right
          fitsOnLeft = limits.left <= left - pw

          if fitsOnLeft
            return 'left'
          if fitsOnRight
            return 'right'
          else
            return 'top'

        setupPreviewOverlay: ->
          options =
            container: @el
            containment: '.im-query-results'
            html: true
            title: @model.get '_type'
            trigger: intermine.options.CellPreviewTrigger
            delay: {show: 700, hide: 250} # Slight delays to prevent jumpiness.
            classes: 'im-cell-preview'
            content: @getPopoverContent
            placement: @getPopoverPlacement

          @$el.on 'shown', => @cellPreview.reposition()
          @$el.on 'shown', => @options.query.trigger 'showing:preview', @el
          @$el.on 'show', (e) => e.preventDefault() if @model.get 'is:selecting'

          @cellPreview = new intermine.bootstrap.DynamicPopover @el, options


        updateValue: ->
          @$('.im-displayed-value').html @formatter(@model)

        selectingStateChange: ->
          {selected, selectable, selecting} = @model.selectionState()
          @$el.toggleClass "active", selected
          @$('input').attr checked: selected
          @$('input').attr disabled: not selectable
          @$('input').toggle selecting and selectable

        getData: ->
          {IndicateOffHostLinks, ExternalLinkIcons} = intermine.options
          field = @options.field
          data =
            value: @model.get field
            field: field
            url: @model.get('service:url')
            host: if IndicateOffHostLinks then window.location.host else /.*/
            icon: null

          unless /^http/.test(data.url)
            data.url = @model.get('service:base') + data.url

          for domain, url of ExternalLinkIcons when data.url.match domain
            data.icon ?= url
          data

        render: ->
          @$el.html CELL_HTML @getData()
          @model.trigger 'change'
          @setupPreviewOverlay() if @model.get('id')
          this

        setWidth: (w) -> # no-op. Was used, but can be removed when all callers are.
          this

        activateChooser: ->
          {selected, selectable, selecting} = @model.selectionState()
          if selectable and selecting
            @model.set 'is:selected': not selected

    class NullCell extends Cell
        setupPreviewOverlay: ->

        initialize: ->
          @model = new intermine.model.NullObject()
          super()

    scope "intermine.results.table", {NullCell, SubTable, Cell}


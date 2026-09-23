# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# coffeelint: disable=camel_case_classes
class App.UiElement.grouped_select extends App.UiElement.ApplicationUiElement
  @render: (attributeConfig, params) ->
    attribute = $.extend(true, {}, attributeConfig)

    # Load groups from relation
    groups = App.Group.all().filter((g) -> g.active)

    parents = {}
    children = {}

    for group in groups
      parts = group.name.split('::')
      if parts.length is 1
        parents[group.name] = group
      else
        topParent = parts[0]
        children[topParent] ?= []
        children[topParent].push(group)

    select = $('<select>')
      .attr('name', attribute.name)
      .attr('id', attribute.id || attribute.name)
      .addClass('form-control')
    select.attr('required', true) if !attribute.null

    select.append($('<option value="">').text('-'))

    sortedParents = _.sortBy(Object.keys(parents))
    for parentName in sortedParents
      parent = parents[parentName]
      kids = children[parentName] || []
      if kids.length > 0
        optgroup = $('<optgroup>').attr('label', parent.name_last || parentName)
        for child in _.sortBy(kids, (g) -> g.name_last || g.name)
          label = child.name.replace(/^.*::/, '')
          option = $('<option>').val(child.id).text(label)
          option.prop('selected', true) if String(attribute.value) is String(child.id)
          optgroup.append(option)
        select.append(optgroup)
      else
        option = $('<option>').val(parent.id).text(parent.name_last || parentName)
        option.prop('selected', true) if String(attribute.value) is String(parent.id)
        select.append(option)

    $('<div class="controls">').append(select)

# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# coffeelint: disable=camel_case_classes
class App.UiElement.grouped_select extends App.UiElement.ApplicationUiElement
  @render: (attributeConfig, params) ->
    attribute = $.extend(true, {}, attributeConfig)

    groups = App.Group.all().filter((g) -> g.active)

    # Build parent-child map: key = full parent name, value = array of direct children
    childrenOf = {}
    groupByName = {}
    for group in groups
      groupByName[group.name] = group
      parts = group.name.split('::')
      if parts.length > 1
        parentName = parts.slice(0, -1).join('::')
        childrenOf[parentName] ?= []
        childrenOf[parentName].push(group)

    # A leaf is a group with no children
    isLeaf = (name) -> !childrenOf[name]?.length

    select = $('<select>')
      .attr('name', attribute.name)
      .attr('id', attribute.id || attribute.name)
      .addClass('form-control')
    select.attr('required', true) if !attribute.null
    select.append($('<option value="">').text('-'))

    # Recursively build optgroups for parent nodes, options for leaves
    buildOptions = (parentName, breadcrumb) =>
      kids = childrenOf[parentName] || []
      return unless kids.length

      leaves = _.sortBy(kids.filter((g) -> isLeaf(g.name)), (g) -> g.name_last || g.name)
      branches = _.sortBy(kids.filter((g) -> !isLeaf(g.name)), (g) -> g.name_last || g.name)

      if leaves.length
        optgroup = $('<optgroup>').attr('label', breadcrumb)
        for child in leaves
          label = child.name_last || child.name.replace(/^.*::/, '')
          option = $('<option>').val(child.id).text(label)
          option.prop('selected', true) if String(attribute.value) is String(child.id)
          optgroup.append(option)
        select.append(optgroup)

      for branch in branches
        branchLabel = branch.name_last || branch.name.replace(/^.*::/, '')
        buildOptions(branch.name, "#{breadcrumb} › #{branchLabel}")

    # Process top-level groups
    topLevel = _.sortBy(groups.filter((g) -> g.name.indexOf('::') is -1), (g) -> g.name)
    for group in topLevel
      if isLeaf(group.name)
        option = $('<option>').val(group.id).text(group.name_last || group.name)
        option.prop('selected', true) if String(attribute.value) is String(group.id)
        select.append(option)
      else
        buildOptions(group.name, group.name_last || group.name)

    wrapper = $('<div class="controls controls--select">')
    wrapper.append(select)
    wrapper[0].insertAdjacentHTML('beforeend', '<svg class="icon icon-arrow-down"><use xlink:href="assets/images/icons.svg#icon-arrow-down"></use></svg>')
    wrapper

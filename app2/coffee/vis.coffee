
root = exports ? this

# Help with the placement of nodes
RadialPlacement = () ->
  # stores the key -> location values
  values = d3.map()
  # how much to separate each location by
  increment = 20
  # how large to make the layout
  radius = 200
  # where the center of the layout should be
  center = {"x":0, "y":0}
  # what angle to start at
  start = -120
  current = start

  # Given an center point, angle, and radius length,
  # return a radial position for that angle
  radialLocation = (center, angle, radius) ->
    x = (center.x + radius * Math.cos(angle * Math.PI / 180))
    y = (center.y + radius * Math.sin(angle * Math.PI / 180))
    {"x":x,"y":y}

  # Main entry point for RadialPlacement
  # Returns location for a particular key,
  # creating a new location if necessary.
  placement = (key) ->
    value = values.get(key)
    if !values.has(key)
      value = place(key)
    value

  # Gets a new location for input key
  place = (key) ->
    value = radialLocation(center, current, radius)
    values.set(key,value)
    current += increment
    value

   # Given a set of keys, perform some 
  # magic to create a two ringed radial layout.
  # Expects radius, increment, and center to be set.
  # If there are a small number of keys, just make
  # one circle.
  setKeys = (keys) ->
    # start with an empty values
    values = d3.map()
  
    # number of keys to go in first circle
    firstCircleCount = 360 / increment

    # if we don't have enough keys, modify increment
    # so that they all fit in one circle
    if keys.length < firstCircleCount
      increment = 360 / keys.length

    # set locations for inner circle
    firstCircleKeys = keys.slice(0,firstCircleCount)
    firstCircleKeys.forEach (k) -> place(k)

    # set locations for outer circle
    secondCircleKeys = keys.slice(firstCircleCount)

    # setup outer circle
    radius = radius + radius / 1.8
    increment = 360 / secondCircleKeys.length

    secondCircleKeys.forEach (k) -> place(k)

  placement.keys = (_) ->
    if !arguments.length
      return d3.keys(values)
    setKeys(_)
    placement

  placement.center = (_) ->
    if !arguments.length
      return center
    center = _
    placement

  placement.radius = (_) ->
    if !arguments.length
      return radius
    radius = _
    placement

  placement.start = (_) ->
    if !arguments.length
      return start
    start = _
    current = start
    placement

  placement.increment = (_) ->
    if !arguments.length
      return increment
    increment = _
    placement

  return placement

Network = () ->
  # allData stores the unfiltered data
  # variables we want to access
  # in multiple places of Network
  width = 960
  height = 800
  allData = []
  curLinksData = []
  curNodesData = []
  linkedByIndex = {}
  # these will hold the svg groups for
  # accessing the nodes and links display
  nodesG = null
  linksG = null
  # these will point to the circles and lines
  # of the nodes and links
  node = null
  link = null
  # variables to refect the current settings
  # of the visualization
  layout = "force"
  filter = "all"
  sort = "songs"
  # groupCenters will store our radial layout for
  # the group by artist layout.
  groupCenters = null

  # our force directed layout
  force = d3.layout.force()
  # color function used to color nodes
  nodeColors = d3.scale.category20()
  # tooltip used to display details
  tooltip = Tooltip("vis-tooltip")

  # charge used in artist layout
  charge = (node) -> -Math.pow(node.radius, 2.0) / 2

  # Starting point for network visualization
  # Initializes visualization and starts force layout
  network = (selection, data) ->
    # format our data
    allData = setupData(data)
   

    # create our svg and groups
    vis = d3.select(selection).append("svg")
      .attr("width", width)
      .attr("height", height)
    linksG = vis.append("g").attr("id", "links")
    nodesG = vis.append("g").attr("id", "nodes")

    # setup the size of the force environment
    force.size([width, height])

    setLayout("force")
    setFilter("all")
    

    # perform rendering and start force layout
    update()

  # The update() function performs the bulk of the
  # work to setup our visualization based on the
  # current layout/sort/filter.
  #
  # update() is called everytime a parameter changes
  # and the network needs to be reset.
  update = () ->
    # filter data to show based on current filter settings.
    curNodesData = filterNodes(allData.nodes)
    curLinksData = filterLinks(allData.links, curNodesData)

    # sort nodes based on current sort and update centers for
    # radial layout
    if layout == "radial"
      categories = sortedCategories(curNodesData, curLinksData)
      updateCenters(categories)

    # reset nodes in force layout
    force.nodes(curNodesData)

    # enter / exit for nodes
    updateNodes()

    # always show links in force layout
    if layout == "force"
      force.links(curLinksData)
      updateLinks()
    else
      # reset links so they do not interfere with
      # other layouts. updateLinks() will be called when
      # force is done animating.
      force.links([])
      # if present, remove them from svg 
      if link
        link.data([]).exit().remove()
        link = null

    # start me up!
    force.start()

  # Public function to switch between layouts
  network.toggleLayout = (newLayout) ->
    force.stop()
    setLayout(newLayout)
    update()

  # Public function to switch between filter options
  network.toggleFilter = (newFilter) ->
    force.stop()
    setFilter(newFilter)
    update()

  # Public function to switch between sort options
  network.toggleSort = (newSort) ->
    force.stop()
    setSort(newSort)
    update()

  # Public function to update highlighted nodes
  # from search
  network.updateSearch = (searchTerm) ->
    searchRegEx = new RegExp(searchTerm.toLowerCase())
    total = 0
    node.each (d) ->
      element = d3.select(this)
      match = d.data.name.toLowerCase().search(searchRegEx)
      if searchTerm.length > 0 and match >= 0
        element.style("fill", "#FF0")
          .style("stroke", "#000")
        d.searched = true
        total++
      else
        d.searched = false
        element.style("fill", (d) -> d.data.color )
          .style("stroke", (d) -> strokeFor(d) )
      if total == 0 
        $("#searched").html("")
      else 
        $("#searched").html(total+" Mal gefunden");

  network.updateData = (newData) ->
    allData = setupData(newData)
    link.remove()
    node.remove()
    update()


  network.hilight = (r,d) ->
    showDetails.apply(r,d)

  # called once to clean up raw data and switch links to
  # point to node instances
  # Returns modified data
  setupData = (data) ->
    # initialize circle radius scale
    countExtent = d3.extent(data.nodes, (d) -> d.data.count)
    circleRadius = d3.scale.sqrt().range([3, 12]).domain(countExtent)
    data.nodes.forEach (n) ->
      # set initial x/y to values within the width/height
      # of the visualization
      n.x = Math.floor(Math.random()*width)
      n.y = Math.floor(Math.random()*height)
      # add radius to the node so we can use it later
      n.radius = circleRadius(n.data.count)

    # id's -> node objects
    nodesMap  = mapNodes(data.nodes)

    # switch links to point to node objects instead of id's
    data.links.forEach (l) ->
      l.source = nodesMap.get(l.source) 
      l.target = nodesMap.get(l.target)
      if typeof l.source == "undefined"
        log "link #{l.id} has no valid source"
      if typeof l.target == "undefined"
        log "link #{l.id} has no valid target"
      # linkedByIndex is used for link sorting
      try
        linkedByIndex["#{l.source.id},#{l.target.id}"] = 1
      catch e
        log("Fehler "+e+l.source)
    
    data

  # Helper function to map node id's to node objects.
  # Returns d3.map of ids -> nodes
  mapNodes = (nodes) ->
    nodesMap = d3.map()
    nodes.forEach (n) ->
      if typeof n.id != "undefined" 
        nodesMap.set(n.id, n)
      else 
        log "Node #{n.data.name} has no id"  
    nodesMap

  # Helper function that returns an associative array
  # with counts of unique attr in nodes
  # attr is value stored in node, like 'artist'
  nodeCounts = (nodes, attr) ->
    counts = {}
    nodes.forEach (d) ->
      counts[d.data[attr]] ?= 0
      counts[d.data[attr]] += 1
    counts

  # Given two nodes a and b, returns true if
  # there is a link between them.
  # Uses linkedByIndex initialized in setupData
  neighboring = (a, b) ->
    linkedByIndex[a.id + "," + b.id] or
      linkedByIndex[b.id + "," + a.id]

  # Removes nodes from input array
  # based on current filter setting.
  # Returns array of nodes
  filterNodes = (allNodes) ->
    filteredNodes = allNodes
    countnodes = allNodes.filter (n) ->
      n.type=='i'
    if filter == "popular" or filter == "obscure"
      counts = countnodes.map((d) -> d.data.count).sort(d3.ascending)
      cutoff = d3.quantile(counts, 0.5)
      filteredNodes = allNodes.filter (n) ->
        if filter == "popular"
          (n.type=="t") || (n.data.count > cutoff)
        else if filter == "obscure"
          (n.type=="t") || (n.data.count <= cutoff)

    filteredNodes

  # Returns array of artists sorted based on
  # current sorting method.
  sortedCategories = (nodes,links) ->
    categories = []
    counts={}
    nodes.forEach (n) ->
      counts[n.data.category] ?=0
      counts[n.data.category] +=1
    # sort based on counts
    categories = d3.entries(counts).sort (a,b) ->
      b.value - a.value
    console.log(categories)
    # get just names
    # categories = categories.map (v) -> v.name
    # else
    #  counts = nodeCounts(nodes, "count")
    #  categories = d3.entries(counts).sort (a,b) ->
    #    b.value - a.value
    #  categories = categories.map (v) -> v.name
    categories.map (v) -> v.key

  updateCenters = (categories) ->
    if layout == "radial"
      groupCenters = RadialPlacement().center({"x":width/2, "y":height / 2 - 100})
        .radius((height/2)-100).increment(18).keys(categories)

  # Removes links from allLinks whose
  # source or target is not present in curNodes
  # Returns array of links
  filterLinks = (allLinks, curNodes) ->
    curNodes = mapNodes(curNodes)
    allLinks.filter (l) ->
      curNodes.get(l.source.id) and curNodes.get(l.target.id)

  # enter/exit display for nodes
  updateNodes = () ->
    node = nodesG.selectAll("circle.node")
      .data(curNodesData, (d) -> d.id)

    node.enter().append("circle")
      .attr("class", (d) -> "node node-"+d.type)
      .attr("cx", (d) -> d.x)
      .attr("cy", (d) -> d.y)
      .attr "r", (d) -> 
        if d.type == 'i' 
          d.radius
        else 
          d.radius*3
      .style("fill", (d) -> d.data.color)
      .style "fill-opacity", (d) -> 
        if d.type == "i" 
          1.0 
        else 
          0.4
      .style("stroke", (d) -> strokeFor(d))
      .style "stroke-width", (d) ->
        if d.type == "i" 
          1.0
        else 
          d.radius / 2
      .call force.drag

    node.on("mouseover", showDetails)
      .on("mouseout", hideDetails)

    node.exit().remove()

  # enter/exit display for links
  updateLinks = () ->
    link = linksG.selectAll("line.link")
      .data(curLinksData, (d) -> "#{d.source.id}_#{d.target.id}")
    link.enter().append("line")
      .attr("class", (d) -> "link link-"+d.type)
      .attr("stroke", "#ddd")
      .attr("stroke-opacity", 0.8)
      .attr("x1", (d) -> d.source.x)
      .attr("y1", (d) -> d.source.y)
      .attr("x2", (d) -> d.target.x)
      .attr("y2", (d) -> d.target.y)

    link.exit().remove()

  # switches force to new layout parameters
  setLayout = (newLayout) ->
    layout = newLayout
    if layout == "force"
      force.on("tick", forceTick)
        .charge(-200)
        .linkDistance(50)
    else if layout == "radial"
      force.on("tick", radialTick)
        .charge(charge)
    else if layout == "focus"
      force.on("tick", focusTick)

  # switches filter option to new filter
  setFilter = (newFilter) ->
    filter = newFilter

  # switches sort option to new sort
  setSort = (newSort) ->
    sort = newSort

  # tick function for force directed layout
  forceTick = (e) ->
    node
      .attr("cx", (d) -> d.x)
      .attr("cy", (d) -> d.y)

    link
      .attr("x1", (d) -> d.source.x)
      .attr("y1", (d) -> d.source.y)
      .attr("x2", (d) -> d.target.x)
      .attr("y2", (d) -> d.target.y)

  # tick function for radial layout
  radialTick = (e) ->
    node.each(moveToRadialLayout(e.alpha))

    node
      .attr("cx", (d) -> d.x)
      .attr("cy", (d) -> d.y)

    if e.alpha < 0.03
      force.stop()
      updateLinks()

  # Adjusts x/y for each node to
  # push them towards appropriate location.
  # Uses alpha to dampen effect over time.
  moveToRadialLayout = (alpha) ->
    k = alpha * 0.1
    (d) ->
      centerNode = groupCenters(d.data.category)
      d.x += (centerNode.x - d.x) * k
      d.y += (centerNode.y - d.y) * k


  # Helper function that returns stroke color for
  # particular node.
  strokeFor = (d) ->
    if !d.searched
      d3.rgb(d.data.color).darker().toString()
    else 
      "#FF00FF"

  # Mouseover tooltip function
  showDetails = (d,i) ->
    if d.type == 'i'
      tooltip.showTooltip(renderer.render("gedanke",d),d3.event)
    else
      tooltip.showTooltip(renderer.render("thema",d),d3.event)
    # higlight connected links
    if link
      link.attr("stroke", (l) ->
        if l.source == d or l.target == d then "#555" else "#ddd"
      )
        .attr("stroke-opacity", (l) ->
          if l.source == d or l.target == d then 1.0 else 0.5
        )

      # link.each (l) ->
      #   if l.source == d or l.target == d
      #     d3.select(this).attr("stroke", "#555")

    # highlight neighboring nodes
    # watch out - don't mess with node if search is currently matching
    node.style("stroke", (n) ->
      if (n.searched or neighboring(d, n)) then "#555" else strokeFor(n))
  
    # highlight the node being moused over
    d3.select(this).style("stroke","black")

  # Mouseout function
  hideDetails = (d,i) ->
    tooltip.hideTooltip()
    # watch out - don't mess with node if search is currently matching
    node.style("stroke", (n) -> if !n.searched then strokeFor(n) else "#555")
    if link
      link.attr("stroke", "#ddd")
        .attr("stroke-opacity", 0.8)
        
        

  # Final act of Network() function is to return the inner 'network()' function.
  return network

# Activate selector button
activate = (group, link) ->
  d3.selectAll("##{group} a").classed("active", false)
  d3.select("##{group} ##{link}").classed("active", true)

$ ->
  # nach dem Spreadsheet  
  myNetwork = Network()
  window.nw=myNetwork

  d3.selectAll("#layouts a").on "click", (d) ->
    newLayout = d3.select(this).attr("id")
    activate("layouts", newLayout)
    myNetwork.toggleLayout(newLayout)

  d3.selectAll("#filters a").on "click", (d) ->
    newFilter = d3.select(this).attr("id")
    activate("filters", newFilter)
    myNetwork.toggleFilter(newFilter)

  d3.selectAll("#sorts a").on "click", (d) ->
    newSort = d3.select(this).attr("id")
    activate("sorts", newSort)
    myNetwork.toggleSort(newSort)

  $("#search").keyup () ->
    searchTerm = $(this).val()
    myNetwork.updateSearch(searchTerm)

  ## key: 
    	
  
  frag=$(document).aciFragment "api"

  Tabletop.init key : frag.get("key") || "0AnjSydpjIFuXdE9sUXpRRGtnd1liWVFqNXRtcXM2MUE", columnLabels: true, parseNumbers: true, callback: (data) -> 
    settings  = makesettings data.settings.elements
    templates = makesettings data.templates.elements
    data	  = makedata(data.matrix, settings)
    window.renderer=ECT({ root: templates })
    $("h1").fadeOut
      complete : () ->
        $("h1").html(settings.title).fadeIn()
        $("#rest").fadeIn()
    myNetwork("#vis", data)
    
  makesettings = (list) ->
    r={}
    _.each list, (e) -> 
  	  try
  	    v=(new Function("return ("+e.value+")"))()
      catch ex
        log "settings["+e.name+"] - '"+e.value+"' taken as literal. Evaluating yielded: "+ex 
        v=e.value
      r[e.name]=v
    r

  makeid = (index,prefix) ->
    if prefix?
      prefix+index
    else 
      "id"+index
	
  makedata = (matrix,settings) ->
    topics={};
    nodes=[];
    links=[];
    if window.debug
      window.settings=settings;
      window.matrix=matrix;
      window.topics=topics;
      window.nodes=nodes;
    start=settings.startheader.charCodeAt(0)-"A".charCodeAt(0)
    links.push
      source : makeid matrix.column_labels.length-(start+1)
      target : makeid 0
      type   : "tt" 
      id	 : makeid(links.length,"l")
    _(matrix.column_labels).each (e,i) ->
      if i>=start
        n=matrix.column_names[i];
        topics[n] = 
          count	: 0
          sum 	: 0
          id 	: makeid nodes.length
          name	: e
          index	: nodes.length
          color	: settings.colors[i % settings.colors.length]
          items	: []
        topics[n].category=topics[n].id
        nodes.push
          id 	: topics[n].id
          type	: "t"
          data	: topics[n] 
        if nodes.length>1
          links.push 
            source 	: makeid nodes.length-1
            target	: makeid nodes.length-2 
            type	: "tt"
            id		: makeid(links.length,"l")
    _(matrix.elements).each (d,i) ->
      o= 
        id		: d.id
        name	: d.wortmeldung
        topics	: []
        count 	: d.anzahl
        color	: "#000000"
      source=d.id;
      _(_(topics).keys()).each (n) ->
        if (typeof d[n] != "undefined") && (d[n])
          o.topics.push topics[n]
          o.category=topics[n].category
          topics[n].count+=1
          topics[n].sum+=parseInt d.anzahl
          topics[n].items.push o
          links.push 
            source: source
            target: topics[n].id
            type : "it"
            color : topics[n].color
      if o.topics.length > 1 
        o.color="#000000"
      else 
        o.color=o.topics[0].color
      nodes.push
        id		: o.id
        type 	: "i"
        data	: o
    nodes.forEach (n) ->
      if n.type=="t"
        n.data.items.sort (a,b) ->
          b.count - a.count
      else 
        n.data.topics.sort (a,b) ->
          b.sum - a.sum
    r =      
      nodes: nodes
      links: links


PADDING = 5
INDENT_SPACING = 10
TOUNGE_HEIGHT = 10

class BoundingBoxState
  constructor: (point) ->
    @x = point.x
    @y = point.y

class PathWaypoint
  constructor: (@left, @right) ->

class IceView

  constructor: (@block) ->
    @children = [] # All child blocks, for event delegation. (IceView[])
    
    # Start and end lines
    @lineStart = @lineEnd = null

    @lineChildren = {} # Children on each line, computed in FIRST PASS (int:IceView[])

    @dimensions = {} # Bounding box on each line, computed in SECOND PASS (int:draw.Size)

    @indented = {}

    @indentEndsOn = {}

    @pathWaypoints = {} # PathWaypoint[]

    @bounds = {} # Bounding boxes on each line, computed in THIRD PASS (int:draw.Rectangle)

  # FIRST PASS: generate @lineChildren and @children
  computeChildren: (line) -> # (line) is the starting line

    # Record the starting line
    @lineStart = line

    # Linked-list loop through inner tokens
    head = @block.start.next
    while head isnt @block.end
      switch head.type
        when 'blockStart'
          # Ask this child to compute its children (thus determining its ending line, as well)
          line = head.block.view.computeChildren line

          # Append to children array
          @children.push head.block.view

          # Append to line children array
          for occupiedLine in [head.block.view.lineStart..head.block.view.lineEnd] # (iterate over all lines which this indent occupies)
            # (initialize empty array if it doesn't already exist
            @lineChildren[occupiedLine] ?= []

            # Push to the children on this line
            @lineChildren[occupiedLine].push head.block.view

            @indented[occupiedLine] ||= head.block.view.indented[occupiedLine]
            @indentEndsOn[occupiedLine] ||= head.block.view.indentEndsOn[occupiedLine]

          # Skip to the end of this indent
          head = head.block.end

        when 'indentStart'
          # Act analagously for indents
          line = head.indent.view.computeChildren line

          # Append to children array
          @children.push head.indent.view

          # Append to line children array
          for occupiedLine in [head.indent.view.lineStart..head.indent.view.lineEnd] # (iterate over all lines which this indent occupies)
            # (initialize empty array if it doesn't already exist
            @lineChildren[occupiedLine] ?= []

            # Push to the children on this line
            @lineChildren[occupiedLine].push head.indent.view
            
            # Mark that this line is indented here in this block
            @indented[occupiedLine] = true

          @indentEndsOn[head.indent.view.lineEnd] = true

          # Skip to the end of this indent
          head = head.indent.end

        when 'text', 'cursor'
          # Act analagously for text and cursor
          head.view.computeChildren line
          
          # (For text and cursor the token itself is also the manifested thing)
          @children.push head.view
          
          @lineChildren[line] ?= []; @lineChildren[line].push head.view

        when 'newline'
          line += 1
      
      # Advance our head token (linked-loop list)
      head = head.next
    
    # Record the last line
    @lineEnd = line

    return line
  
  # SECOND PASS: compute dimensions on each line
  computeDimensions: -> # A block's dimensions on each line is strictly a function of its children, so this function has no arguments.
    # Event propagate
    for child in @children then child.computeDimensions()

    return @dimensions
  
  # THIRD PASS: compute bounding boxes on each line
  computeBoundingBox: (line, state) -> # (line) and (state) are given by the calling parent and signify restrictions on the position of the line (e.g. padding, etc).
    console.log 'delegated to super from type', @block.type
    # Event propagate
    for child in @lineChildren[line] then child.computeBoundingBox line, state # In an instance of this function, you will want to change (state) as you move along @lineChildren[line], to adjust for padding and such.

    return @bounds[line] = new draw.NoRectangle() # Should actually equal something

  # Convenience function: computeBoundingBoxes. Normally only called on root or floating block.
  computeBoundingBoxes: ->
    cursor = new draw.Point 0, 0
    for line in [@lineStart..@lineEnd]
      @computeBoundingBox line, new BoundingBoxState cursor
      cursor.y += @dimensions[line]

    return @bounds

  # FOURTH PASS: join "path bits" into a path
  computePath: ->
    # Event propagate
    for child in @children then child.computePath()

    return @bounds

  # FIFTH PASS: draw
  draw: (ctx) ->
    # Event propagate
    for child in @children then child.draw ctx

  # Convenience function: compute
  compute: (line = 0) ->
    @computeChildren line
    @computeDimensions(); @computeBoundingBoxes(); @computePath()

  finish: -> # Deprecated.

class BlockView extends IceView
  constructor: (block) ->
    super block
    @path = null

  computeDimensions: ->
    # Event propagate, and any other necessary wrappers
    super

    for line in [@lineStart..@lineEnd]
      width = PADDING; height = 2 * PADDING

      for child in @lineChildren[line]

        console.log line, child, child.dimensions[line]

        if child.block.type is 'indent'
          # The width of a block on a line is the sum of the widths of the child blocks, plus padding.
          width += child.dimensions[line].width + INDENT_SPACING

          # The height of a block on a line is the maximum height of a child block, plus padding.
          # We add 10 if the indent ends, so as to draw the bottom of the mouth.
          height = Math.max height, child.dimensions[line].height + (if child.lineEnd is line then TOUNGE_HEIGHT else 0)

        else if child.indented[line]
          width += child.dimensions[line].width + PADDING

          # The height of a block on a line is the maximum height of a child block. Indented things do not use any padding.
          height = Math.max height, child.dimensions[line].height

        else
          width += child.dimensions[line].width + PADDING

          # The height of a block on a line is the maximum height of a child block, plus padding.
          height = Math.max height, child.dimensions[line].height + 2 * PADDING

      @dimensions[line] = new draw.Size width, height

  computeBoundingBox: (line, state) ->

    # Find the middle of this rectangle
    axis = state.y + @dimensions[line].height / 2
    cursor = state.x
    
    # Accept the bounds given by our parent.
    @bounds[line] = new draw.Rectangle state.x, state.y, @dimensions[line].width, @dimensions[line].height

    console.log line, @bounds[line]

    for child in @lineChildren[line]
      # Special case for indented things; always jam them together.
      if child.indented[line]
        # Add the padding on the left of this
        cursor += INDENT_SPACING

        child.computeBoundingBox line, new BoundingBoxState new draw.Point cursor,
          state.y # Position the child at the top of the line.
      
      else
        # Add the padding on the left of this
        cursor += PADDING

        child.computeBoundingBox line, new BoundingBoxState new draw.Point cursor,
          axis - child.dimensions[line].height / 2 # Position the child in the middle of the line

      cursor += child.dimensions[line].width

    # Compute the path waypoints
    if @lineChildren[line].length is 0 or not @lineChildren[line][0].indented[line]
      ###
      # Normally, we just enclose everything within these bounds
      ###
      @pathWaypoints[line] = new PathWaypoint [
        new draw.Point @bounds[line].x, @bounds[line].y
        new draw.Point @bounds[line].x, @bounds[line].bottom()
      ], [
        new draw.Point @bounds[line].right(), @bounds[line].y
        new draw.Point @bounds[line].right(), @bounds[line].bottom()
      ]

    else if @lineChildren[line].length > 0
      ###
      # There is, however, the special case when a child on this line is indented, or is an indent.
      ###

      if @lineChildren[line][0].indentEndsOn[line]
        ###
        # If the indent ends on this line, we draw the piece underneath it, and any 'G'-shape elements after it.
        ###

        # We name this for conveniency
        indentedChild = @lineChildren[line][0]

        if @lineChildren[line].length is 1
          @pathWaypoints[line] = new PathWaypoint [
            # The line down the left of the child
            new draw.Point @bounds[line].x, @bounds[line].y
            new draw.Point @bounds[line].x, @bounds[line].bottom()
          ], [
            # The box to the left of the child
            new draw.Point @bounds[line].x + INDENT_SPACING, @bounds[line].y
            new draw.Point @bounds[line].x + INDENT_SPACING, indentChild.bounds[line].bottom()
            
            # The 'tounge' underneath the child
            new draw.Point indentChild.bounds[line].right(), indentChild.bounds[line].bottom()
            
            # For robustness, make sure that we go all the way to the right here.
            new draw.Point @bounds[line].right(), indentChild.bounds[line].bottom()

            # Pop down to the bottom, ready for next rectangle.
            new draw.Point @bounds[line].right(), @bounds[line].bottom()
          ]

        else
          @pathWaypoints[line] = new PathWaypoint [
            # The line down the left of the child
            new draw.Point @bounds[line].x, @bounds[line].y
            new draw.Point @bounds[line].x, @bounds[line].bottom()
          ], [
            # The box to the left of the child
            new draw.Point @bounds[line].x + INDENT_SPACING, @bounds[line].y
            new draw.Point @bounds[line].x + INDENT_SPACING, indentChild.bounds[line].bottom()
            
            # The 'tounge' underneath the child
            new draw.Point indentChild.bounds[line].right(), indentChild.bounds[line].bottom()

            # The 'hook' of the G, coming up from the tounge
            new draw.Point indentChild.bounds[line].right(), @bounds[line].y

            # Finish the box, ready for next rectangle.
            new draw.Point @bounds[line].right(), @bounds[line].y
            new draw.Point @bounds[line].right(), @bounds[line].bottom()
          ]

      else
        ###
        # When the child in front of us is indented, we only draw a thin strip
        # of conainer block to the left of them, with width INDENT_SPACING
        ###
        @pathWaypoints[line] = new PathWaypoint [
          # (Left side)
          new draw.Point @bounds[line].x, @bounds[line].y
          new draw.Point @bounds[line].x, @bounds[line].bottom()
        ], [
          # (Right side)
          new draw.Point @bounds[line].x + INDENT_SPACING, @bounds[line].y
          new draw.Point @bounds[line].x + INDENT_SPACING, @bounds[line].bottom()
        ]

  computePath: ->
    super

    @path = new draw.Path []

    console.log @pathWaypoints

    for line, waypoint of @pathWaypoints
      for point in waypoint.left
        @path.unshift point
      for point in waypoint.right
        @path.push point

    console.log @path

    @path.style.fillColor = @block.color
    @path.style.strokeColor = '#000'
    
  draw: (ctx) ->
    @path.draw ctx

    super

class TextView extends IceView
  constructor: (block) ->
    super block
    @textElement = null
    
  computeChildren: (line) ->
    # A text element cannot contain anything
    @lineStart = @lineEnd = line

  computeDimensions: ->
    # Construct a manifest text element for this text token
    @textElement = new draw.Text new draw.Point(0, 0),
      @block.value
    
    # A text element only occupies one line
    @dimensions[@lineStart] = new draw.Size @textElement.bounds().width,
      @textElement.bounds().height

    console.log @dimensions

    return @dimesions
  
  computeBoundingBox: (line, state) ->
    # Move the text element to where we want it to go
    if line is @lineStart
      @textElement.setPosition new draw.Point state.x, state.y
  
  computePath: -> # Do nothing

  draw: (ctx) ->
    @textElement.draw ctx

class IndentView extends IceView
  constructor: (block) ->
    super block

  computeChildren: (line) ->
    super
    console.log @lineStart, @lineEnd

    @lineStart += 1

  computeDimensions: ->
    super
    
    for line in [@lineStart..@lineEnd]
      height = width = 0

      for child in @lineChildren[line]
        # Indents undertake no padding.
        width += child.dimensions[line].width
        height = Math.max height, child.dimensions[line].height
      
      @dimensions[line] = new draw.Size width, height
    
  computeBoundingBox: (line, state) ->
    cursorX = state.x
    cursorY = state.y

    for child in @lineChildren[line]
      child.computeBoundingBox line, new BoundingBoxState new draw.Point cursorX, cursorY
      
      cursorX += child.dimensions[line].width

class SocketView extends IceView
  constructor: (block) -> super block

class SegmentView extends IceView
  constructor: (block) -> super block

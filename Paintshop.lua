--[[
  Whole code is a bit of a mess and definitely needs reworking: splitting in separate modules,
  reorganazing, etc. But at this stage it’s mostly just a small API test.
]]

local sim = ac.getSim()
local uiState = ac.getUI()
local car = ac.getCar(0)
local carDir = ac.getFolder(ac.FolderID.ContentCars)..'/'..ac.getCarID(car.index)
local skinDir = carDir..'/skins/'..ac.getCarSkinID(0)
local carNode = ac.findNodes('carRoot:0')
local carMeshes = carNode:findMeshes('{ ! material:DAMAGE_GLASS & lod:A }')

-- Calling it once at the start to initialize RealTimeStylus API and get Assetto Corsa to work
-- nicely with pens and styluses (check `ac.getPenPressure()` description for more information).
ac.getPenPressure()

local selectedMeshes ---@type ac.SceneReference
local carTexture
local aoTexture

local shortcuts = {
  undo = ui.shortcut({ key = ui.KeyIndex.Z, ctrl = true }, ui.KeyIndex.XButton1),
  redo = ui.shortcut({ key = ui.KeyIndex.Y, ctrl = true }, ui.KeyIndex.XButton2),
  save = ui.shortcut{ key = ui.KeyIndex.S, ctrl = true },
  export = ui.shortcut{ key = ui.KeyIndex.S, ctrl = true, shift = true, alt = true },
  load = ui.shortcut{ key = ui.KeyIndex.O, ctrl = true },
  swapColors = ui.shortcut(ui.KeyIndex.X),
  flipSticker = ui.shortcut(ui.KeyIndex.Z),
  toggleSymmetry = ui.shortcut(ui.KeyIndex.Y),
  toggleDrawThrough = ui.shortcut(ui.KeyIndex.R),
  toolBrush = ui.shortcut(ui.KeyIndex.B),
  toolEraser = ui.shortcut(ui.KeyIndex.E),
  toolStamp = ui.shortcut(ui.KeyIndex.S),
  toolMirroringStamp = ui.shortcut(ui.KeyIndex.K),
  toolBlurTool = ui.shortcut({ key = ui.KeyIndex.B, alt = true }),
  toolEyeDropper = ui.shortcut(ui.KeyIndex.I),
  toolMasking = ui.shortcut(ui.KeyIndex.M),
  toolText = ui.shortcut(ui.KeyIndex.T),
  toggleMasking = ui.shortcut({ key = ui.KeyIndex.M, ctrl = true }),
  toggleOrbitCamera = ui.shortcut({ key = ui.KeyIndex.Space, ctrl = true }),
  toggleProjectOtherSide = ui.shortcut({ key = ui.KeyIndex.E, ctrl = true }),
  arrowLeft = ui.shortcut(ui.KeyIndex.Left),
  arrowRight = ui.shortcut(ui.KeyIndex.Right),
  arrowUp = ui.shortcut(ui.KeyIndex.Up),
  arrowDown = ui.shortcut(ui.KeyIndex.Down),
  opacity = table.range(9, 0, function (index)
    return ui.shortcut(ui.KeyIndex.D0 + index), index
  end)
}

local icons = ui.atlasIcons('res/icons.png', 4, 4, {
  Brush = {1, 1},
  Eraser = {1, 2},
  Undo = {1, 3},
  Redo = {1, 4},
  EyeDropper = {2, 1},
  Camera = {2, 2},
  Save = {2, 3},
  Open = {2, 4},
  Stamp = {3, 1},
  Masking = {3, 2},
  Stencil = {3, 3},
  Export = {3, 4},
  Text = {4, 1},
  MirroringStamp = {4, 2},
  BlurTool = {4, 3},
  MirroringHelper = {4, 4},
})

local taaFix = { On = 1, Off = 0 }

ac.onRelease(function ()
  if carTexture and selectedMeshes then
    selectedMeshes:setMaterialTexture('txDiffuse', carTexture):setMotionStencil(taaFix.Off)
  end
end)

local carPreview ---@type ac.GeometryShot
local hoveredMaterial
local camera ---@type ac.GrabbedCamera
local appVisible = false

local function MeshSelection()
  local ray = render.createMouseRay()
  local ref = ac.emptySceneReference()
  if sim.isWindowForeground and carMeshes:raycast(ray, ref) ~= -1 then
    ui.text('Found:')    
    ui.pushFont(ui.Font.Small)
    ui.text('\tMesh: '..tostring(ref:name()))
    ui.text('\tMaterial: '..tostring(ref:materialName()))
    ui.text('\tTexture: '..tostring(ref:getTextureSlotFilename('txDiffuse')))
    ui.popFont()
    ui.offsetCursorY(20)

    if hoveredMaterial ~= ref:materialName() then
      hoveredMaterial = ref:materialName()
      if carPreview then carPreview:dispose() end
      carPreview = ac.GeometryShot(carNode:findMeshes('{ material:'..hoveredMaterial..' & lod:A }'), vec2(420, 320))
      carPreview:setClearColor(rgbm(0.14, 0.14, 0.14, 1))
    end

    local mat = mat4x4.rotation(ui.time()*0.1, vec3(0, 1, 0)):mul(car.bodyTransform)
    carPreview:update(mat:transformPoint(car.aabbCenter + vec3(0, 2, 4)), mat:transformVector(vec3(0, -1, -2)), nil, 50)
    ui.image(carPreview, vec2(210, 160))
    ui.offsetCursorY(20)

    local size = ui.imageSize(ref:getTextureSlotFilename('txDiffuse'))
    if size.x > 0 and size.y > 0 then
  
      ui.textWrapped('• Hold Shift and click to start drawing.\n• Hold Ctrl+Shift and click to start drawing using custom AO map.')
  
      ui.offsetCursorY(20)
      ui.pushFont(ui.Font.Small)
      ui.textWrapped('For best results, either use a custom AO map or make sure this texture is an AO map (grayscale colors with nothing but shadows).')
      ui.popFont()

      ui.setShadingOffset(1, 0, 1, 1)
      ui.image(ref:getTextureSlotFilename('txDiffuse'), vec2(210, 210 * size.y / size.x))
      ui.resetShadingOffset()

      if uiState.shiftDown and not uiState.altDown and uiState.isMouseLeftKeyClicked and not uiState.wantCaptureMouse then
        if uiState.ctrlDown then
          local _selectedMeshes = carNode:findMeshes('{ material:'..hoveredMaterial..' & lod:A }')
          local _carTexture = ref:getTextureSlotFilename('txDiffuse')
          os.openFileDialog({
            title = 'Open Base AO Map',
            folder = carDir,
            fileTypes = { { name = 'Images', mask = '*.png;*.jpg;*.jpeg;*.dds' } },
            addAllFilesFileType = true,
            flags = bit.bor(os.DialogFlags.PathMustExist, os.DialogFlags.FileMustExist)
          }, function (err, filename)
            if not err and filename then
              selectedMeshes = _selectedMeshes
              carTexture = _carTexture
              aoTexture = filename
              camera = ac.grabCamera('Paintshop')
              if camera then camera.ownShare = 0 end
            end
          end)
        else
          selectedMeshes = carNode:findMeshes('{ material:'..hoveredMaterial..' & lod:A }')
          carTexture = ref:getTextureSlotFilename('txDiffuse')
          aoTexture = nil
          camera = ac.grabCamera('Paintshop')
          if camera then camera.ownShare = 0 end
        end
      end
    else
      ui.text('Texture is missing')
    end
  else
    ui.text('Hover a car mesh to start drawing…')
  end
end

local editingCanvas, aoCanvas, maskingCanvas ---@type ui.ExtraCanvas
local editingCanvasPhase = 0
local lastRay ---@type ray

local stored = ac.storage{
  color = rgbm(0, 0.2, 1, 0.5),
  bgColor = rgbm(1, 1, 1, 1),
  orbitCamera = true,
  projectOtherSide = false,
  eyeDropperRange = 1,
  selectedStickerSet = 2,
  alignSticker = 3,
  activeToolIndex = 1,
  selectedFont = '',
  fontBold = false,
  fontItalic = false,
  hasPen = false
}

local function brushSizeMult(brush)
  local p = ac.getPenPressure()
  if p ~= 1 and not stored.hasPen then stored.hasPen = true end
  return math.lerp(brush.penMinRadiusMult, 1, p)
end

local function brushParams(key, defaultSize, defaultAlpha, extraFields)
  local t = {
    brushTex = '',
    brushSize = defaultSize or 0.05,
    brushAspectMult = 1,
    brushStepSize = 0.005,
    brushAngle = 0,
    brushRandomizedAngle = false,
    brushAlpha = defaultAlpha or 0.5,
    brushMirror = false,
    penMinRadiusMult = 0.05,
    withMirror = false,
    paintThrough = false,
    smoothing = 0
  }
  if extraFields then 
    for k, v in pairs(extraFields) do t[k] = v end
  end
  return ac.storage(t, key)
end

local ignoreMousePress = true
local drawing = false
local brushesDir = __dirname..'/brushes'
local decalsDir = __dirname..'/decals'
local brushes
local stickers
local selectedStickerSet
local selectedBrushOutline ---@type ui.ExtraCanvas
local selectedBrushOutlineDirty = true
local brushDistance = 1
local cameraAngle = vec2(-2.6, 0.1)
local maskingDragging = 0
local changesMade = 0
local saveFilename
-- local maskingCarStored = {} ---@type ac.GeometryShot
local undoStack = {}
local redoStack = {}

local maskingActive = false
local maskingPos = vec3(0, 0.3, 0)
local maskingDir = vec3(0, 1, 0)
local maskingCreatingFrom, maskingCreatingTo
local maskingPoints = {
  vec3(0, 0.3, -1),
  vec3(0, 0.3, 1),
  vec3(-1, 0.3, 0),
  vec3(1, 0.3, 0),
}

local function drawWithAO(baseCanvas, aoTexture)
  -- Draw base editing canvas and apply AO to it. One way of doing it is to use shading offset:
  -- ui.drawImage(aoTexture, 0, ui.windowSize())
  -- ui.setShadingOffset(0, 0, 0, -1)
  -- ui.drawImage(aoTexture, 0, ui.windowSize(), rgbm.colors.black)
  -- ui.resetShadingOffset()

  -- But now there is another way, to use a custom shader:
  ui.renderShader({
    p1 = vec2(),
    p2 = ui.windowSize(),
    blendMode = render.BlendMode.Opaque,
    textures = {
      txBase = baseCanvas,
      txAO = aoTexture
    },
    shader = [[float4 main(PS_IN pin) {
      float4 diffuseColor = txAO.SampleLevel(samLinear, pin.Tex, 0);
      float4 canvasColor = txBase.SampleLevel(samLinear, pin.Tex, 0);
      canvasColor.rgb *= max(diffuseColor.r, max(diffuseColor.g, diffuseColor.b)); // use maximum value of AO RGB color
      canvasColor.a = 1; // return fully opaque texture so that txDetail would not bleed and CMAA2 would be happy
      return canvasColor;
    }]]
  })
end

local function finishEditing()
  selectedMeshes:setMaterialTexture('txDiffuse', carTexture):setMotionStencil(taaFix.Off)
  selectedMeshes = nil
  carTexture = nil
  editingCanvas = nil
  saveFilename = nil
  -- maskingCarView = nil
  undoStack = {}
  redoStack = {}
  changesMade = 0
  ac.setWindowTitle('paintshop', nil)

  if camera then
    local cameraRelease
    cameraRelease = setInterval(function ()
      camera.ownShare = math.applyLag(camera.ownShare, 0, 0.85, ac.getDeltaT())
      if camera.ownShare < 0.001 then
        clearInterval(cameraRelease)
        camera:dispose()
        camera = nil
      end
    end)
  end
end

local function rescanBrushes()
  brushes = table.map(io.scanDir(brushesDir, '*.png'), function (x) return { string.sub(x, 1, #x - 4), brushesDir..'/'..x } end)
end

local function rescanStickers()
  stickers = table.map(io.scanDir(decalsDir, '*'), function (x) return {
    name = x,
    items = table.map(io.scanDir(decalsDir..'/'..x, '*.png'), function (y) return { string.sub(y, 1, #y - 4), decalsDir..'/'..x..'/'..y } end) 
  } end)
  selectedStickerSet = stickers[stored.selectedStickerSet]
end

local accessibleData ---@type ui.ExtraCanvasData

local function maskingBackup()
  local b = stringify({ maskingPos, maskingDir, maskingPoints }, true)
  return function (action)
    if action == 'memoryFootprint' then return 0 end
    if action == 'update' then return maskingBackup() end
    if action == 'dispose' then return end
    maskingPos, maskingDir, maskingPoints = table.unpack(stringify.parse(b))
    maskingActive = true
  end
end

local function addUndo(undo)
  if #undoStack > 29 then
    undoStack[1]('dispose')
    table.remove(undoStack, 1)
  end
  table.insert(undoStack, undo)
  table.clear(redoStack)
  changesMade = changesMade + 1
end

local function stepUndo()
  local last = undoStack[#undoStack]
  if not last then return end
  table.insert(redoStack, last('update'))
  last()
  last('dispose')
  table.remove(undoStack)
  changesMade = changesMade - 1
  editingCanvasPhase = editingCanvasPhase + 1
end

local function stepRedo()
  local last = redoStack[#redoStack]
  if not last then return end
  table.insert(undoStack, last('update'))
  last()
  last('dispose')
  table.remove(redoStack)
  changesMade = changesMade + 1
  editingCanvasPhase = editingCanvasPhase + 1
end

local function undoMemoryFootpring()
  return table.sum(undoStack, function (u) return u('memoryFootprint') end) 
      + table.sum(redoStack, function (u) return u('memoryFootprint') end)
end

local function updateAccessibleData()
  editingCanvasPhase = editingCanvasPhase + 1
  if accessibleData then accessibleData:dispose() end
  editingCanvas:accessData(function (err, data)
    if data then accessibleData = data
    elseif err then ac.warn('Failed to access canvas: '..tostring(err)) end
  end)
end

local autosaveDir = ac.getFolder(ac.FolderID.Cfg)..'/apps/paintshop/autosave'
local autosaveIndex = 1
local autosavePhase = 0

setInterval(function ()
  if not editingCanvas or autosavePhase == editingCanvasPhase or uiState.isMouseLeftKeyDown then return end
  autosavePhase = editingCanvasPhase
  io.createDir(autosaveDir)
  editingCanvas:save(string.format('%s/autosave-%s.zip', autosaveDir, autosaveIndex), ac.ImageFormat.ZippedDDS)
  autosaveIndex = autosaveIndex + 1
  if autosaveIndex == 10 then autosaveIndex = 1 end
end, 20)

local function IconButton(icon, tooltip, active, enabled)
  local r = ui.button('##'..icon, vec2(32, 32), enabled == false and ui.ButtonFlags.Disabled or active and ui.ButtonFlags.Active or ui.ButtonFlags.None)
  ui.addIcon(icon, 24, 0.5, nil, 0)
  if tooltip and ui.itemHovered() then ui.setTooltip(tooltip) end
  return r
end

local function DrawControl()
  ac.setWindowTitle('paintshop', string.gsub(saveFilename and saveFilename or carTexture..' (new)', '.+[/\\:]', '')..(changesMade ~= 0 and '*' or ''))

  if IconButton(icons.Undo, nil, false, #undoStack > 0) or #undoStack > 0 and shortcuts.undo() then
    stepUndo()
  end
  if ui.itemHovered() then    
    ui.setTooltip(string.format('Undo (Ctrl+Z)', #undoStack, math.ceil(undoMemoryFootpring() / (1024 * 1024))))
  end
  ui.sameLine(0, 4)
  if IconButton(icons.Redo, string.format('Redo (Ctrl+Y)', #redoStack), false, #redoStack > 0) or #redoStack > 0 and shortcuts.redo() then
    stepRedo()
  end
  ui.sameLine(0, 4)  
  if IconButton(icons.Open, 'Load image (Ctrl+O)\n\nChoose an image without ambient occlusion, preferably one saved earlier with “Save” button of this tool.\n\nIf you accidentally forgot to save or a crash happened, there are some automatically saved backups\nin “Documents/Assetto Corsa”/cfg/apps/paintshop/autosave”.\n\n(There is also an “Import” option in context menu of this button to add a semi-transparent image on top\nof current one.)') or shortcuts.load() then
    os.openFileDialog({
      title = 'Open',
      folder = skinDir,
      fileTypes = { { name = 'Images', mask = '*.png;*.jpg;*.jpeg;*.dds' } },
    }, function (err, filename)
      if not err and filename then
        ui.setAsynchronousImagesLoading(false)
        addUndo(editingCanvas:backup())
        editingCanvas:clear(rgbm.new(stored.bgColor.rgb, 1)):update(function ()
          ui.unloadImage(filename)
          ui.drawImage(filename, 0, ui.windowSize())
        end)
        setTimeout(updateAccessibleData)
        if not filename:lower():match('%.dds$') then
          saveFilename = filename
        end
        changesMade = 0
      end
    end)
  end
  ui.itemPopup('openMenu', function ()
    if ui.selectable('Clear canvas') then
      addUndo(editingCanvas:backup())
      editingCanvas:clear(rgbm.new(stored.bgColor.rgb, 1))
    end
    if ui.itemHovered() then
      ui.setTooltip('Clears canvas using background (eraser) color')
    end
    if ui.selectable('Import…') then
      os.openFileDialog({
        title = 'Import',
        folder = skinDir,
        fileTypes = { { name = 'Images', mask = '*.png;*.jpg;*.jpeg;*.dds' } },
      }, function (err, filename)
        if not err and filename then
          ui.setAsynchronousImagesLoading(false)
          addUndo(editingCanvas:backup())
          editingCanvas:update(function ()
            ui.unloadImage(filename)
            ui.drawImage(filename, 0, ui.windowSize())
          end)
          setTimeout(updateAccessibleData)
        end
      end)
    end
    if autosaveDir and ui.selectable('Open autosaves folder') then
      io.createDir(autosaveDir)
      os.openInExplorer(autosaveDir)
    end
  end)
  ui.sameLine(0, 4)
  if IconButton(icons.Save, 'Save image (Ctrl+S)\n\nImage saved like that would not have antialiasing or ambient occlusion. To apply texture, use “Export texture”\nbutton on the right.\n\n(There is also a “Save as” option in context menu of this button.)') or shortcuts.save() then
    if saveFilename ~= nil then
      editingCanvas:save(saveFilename)
      changesMade = 0
    else
      os.saveFileDialog({
        title = 'Save Image',
        folder = skinDir,
        fileTypes = { { name = 'PNG', mask = '*.png' }, { name = 'JPEG', mask = '*.jpg;*.jpeg' } },
        fileName = carTexture and string.gsub(carTexture, '.+[/\\:]', ''):gsub('%.[a-zA-Z]+$', '.png'),
        defaultExtension = 'dds',
      }, function (err, filename)
        if not err and filename then
          editingCanvas:save(filename)
          saveFilename = filename
          changesMade = 0
        end
      end)
    end
  end
  ui.itemPopup('saveMenu', function ()
    if ui.selectable('Save as…') then
      os.saveFileDialog({
        title = 'Save Image As',
        folder = skinDir,
        fileTypes = { { name = 'PNG', mask = '*.png' }, { name = 'JPEG', mask = '*.jpg;*.jpeg' } },
        fileName = carTexture and string.gsub(carTexture, '.+[/\\:]', ''):gsub('%.[a-zA-Z]+$', '.png'),
        defaultExtension = 'dds',
      }, function (err, filename)
        if not err and filename then
          editingCanvas:save(filename)
          saveFilename = filename
          changesMade = 0
        end
      end)
    end
    if autosaveDir and ui.selectable('Open autosaves folder') then
      io.createDir(autosaveDir)
      os.openInExplorer(autosaveDir)
    end
  end)
  ui.sameLine(0, 4)  
  if IconButton(icons.Export, 'Export texture (Ctrl+Shift+Alt+S)\n\nImage saved like that is ready to use, with ambient occlusion and everything. To save an intermediate\nresult and continue working on it later, use “Save” button on the left.') or shortcuts.export() then
    os.saveFileDialog({
      title = 'Export Texture',
      folder = skinDir,
      fileTypes = { { name = 'PNG', mask = '*.png' }, { name = 'JPEG', mask = '*.jpg;*.jpeg' }, { name = 'DDS', mask = '*.dds' } },
      fileName = carTexture and string.gsub(carTexture, '.+[/\\:]', ''),
      fileTypeIndex = 3,
      defaultExtension = 'dds',
    }, function (err, filename)
      if not err and filename then
        aoCanvas:update(function (dt)
          drawWithAO(editingCanvas, aoTexture or carTexture)
        end):save(filename)
      end
    end)
  end
  ui.sameLine(0, 4)
  if IconButton(ui.Icons.Leave, changesMade == 0 and 'Finish editing' or 'Cancel editing\nThere are some unsaved changes') then
    if changesMade ~= 0 then
      ui.modalPopup('Cancel editing', 'Are you sure to exit without saving changes?', function (okPressed)
        if okPressed then
          finishEditing()
        end
      end)
    else
      finishEditing()
    end
  end
end

local palette = {
  builtin = { 
    rgbm(1, 1, 1, 1),
    rgbm(0.8, 0.8, 0.8, 1),
    rgbm(0.6, 0.6, 0.6, 1),
    rgbm(1, 0, 0, 1),
    rgbm(1, 0.5, 0, 1),
    rgbm(1, 1, 0, 1),
    rgbm(0.5, 1, 0, 1),
    rgbm(0, 1, 0, 1),
    rgbm(0, 1, 0.5, 1),
    rgbm(0, 1, 1, 1),
    rgbm(0, 0.5, 1, 1),
    rgbm(0, 0, 1, 1),
    rgbm(0.5, 0, 1, 1),
    rgbm(1, 0, 1, 1),
    rgbm(1, 0, 0.5, 1),
    rgbm(0, 0, 0, 1),
    rgbm(0.2, 0.2, 0.2, 1),
    rgbm(0.4, 0.4, 0.4, 1),
    rgbm(1, 0, 0, 1):scale(0.5),
    rgbm(1, 0.5, 0, 1):scale(0.5),
    rgbm(1, 1, 0, 1):scale(0.5),
    rgbm(0.5, 1, 0, 1):scale(0.5),
    rgbm(0, 1, 0, 1):scale(0.5),
    rgbm(0, 1, 0.5, 1):scale(0.5),
    rgbm(0, 1, 1, 1):scale(0.5),
    rgbm(0, 0.5, 1, 1):scale(0.5),
    rgbm(0, 0, 1, 1):scale(0.5),
    rgbm(0.5, 0, 1, 1):scale(0.5),
    rgbm(1, 0, 1, 1):scale(0.5),
    rgbm(1, 0, 0.5, 1):scale(0.5),
  },
  user = stringify.tryParse(ac.storage.palette) or table.range(15, function (index, callbackData)
    return rgbm(math.random(), math.random(), math.random(), 1)
  end)
}

function palette.addToUserPalette(color)
  local _, i = table.findFirst(palette.user, function (item) return item == color end)
  if i ~= nil then
    table.remove(palette.user, i)
  else
    table.remove(palette.user, 1)
  end
  table.insert(palette.user, color:clone())
  ac.storage.palette = stringify(palette.user, true)
end

local function ColorTooltip(color)
  ui.tooltip(0, function ()
    ui.dummy(20)
    ui.drawRectFilled(0, 20, color)
    ui.drawRect(0, 20, rgbm.colors.black)
  end)
end

local editing = false
local colorFlags = bit.bor(ui.ColorPickerFlags.NoAlpha, ui.ColorPickerFlags.NoSidePreview, ui.ColorPickerFlags.PickerHueWheel, ui.ColorPickerFlags.DisplayHex)

local function ColorBlock(key)
  key = key or 'color'
  local col = stored[key]:clone()
  ui.colorPicker('##color', col, colorFlags)
  if ui.itemEdited() then
    stored[key] = col
    editing = true
  elseif editing and not ui.itemActive() then
    editing = false
    palette.addToUserPalette(col)
  end
  for i = 1, #palette.builtin do
    ui.drawRectFilled(ui.getCursor(), ui.getCursor() + 14, palette.builtin[i])
    if ui.invisibleButton(i, 14) then
      stored[key] = palette.builtin[i]:clone()
      palette.addToUserPalette(stored[key])
    end
    if ui.itemHovered() then      
      ColorTooltip(palette.builtin[i])
    end
    ui.sameLine(0, 0)
    if ui.availableSpaceX() < 14 then
      ui.newLine(0)
    end
  end
  for i = 1, #palette.user do
    ui.drawRectFilled(ui.getCursor(), ui.getCursor() + 14, palette.user[i])
    if ui.invisibleButton(100 + i, 14) then
      stored[key] = palette.user[i]:clone()
      palette.addToUserPalette(stored[key])
    end
    if ui.itemHovered() then      
      ColorTooltip(palette.user[i])
    end
    ui.sameLine(0, 0)
  end
  ui.newLine()
  if shortcuts.swapColors() then
    stored[key] = stored[key] == palette.user[#palette.user] and palette.user[#palette.user - 1] or palette.user[#palette.user]
    palette.addToUserPalette(stored[key])
  end
end

local function BrushBaseBlock(brush, maxSize, stickerMode, noStepSize, noSymmetry)
  if not ui.mouseBusy() then
    local w = ui.mouseWheel()
    if ui.keyboardButtonPressed(ui.KeyIndex.SquareOpenBracket, true) then w = w - 1 end
    if ui.keyboardButtonPressed(ui.KeyIndex.SquareCloseBracket, true) then w = w + 1 end
    if w ~= 0 then -- changing brush size with mouse wheel
      if uiState.shiftDown then w = w / 10 end
      if uiState.altDown then
        brush.brushAngle = brush.brushAngle + w * 30
      elseif not uiState.ctrlDown then
        brush.brushSize = math.clamp(brush.brushSize * (1 + w * 0.15), 0.001, maxSize)        
      elseif stickerMode then
        brush.brushAspectMult = math.clamp(brush.brushAspectMult * (1 + w * 0.25), 0.04, 25)
      end
      selectedBrushOutlineDirty = true
    end
    for i = 0, 9 do -- changing opacity photoshop style
      if shortcuts.opacity[i]() then brush.brushAlpha = i == 0 and 1 or i / 10 end
    end
  end

  if stickerMode then
    if ui.checkbox('Flip sticker', brush.brushMirror) or shortcuts.flipSticker() then brush.brushMirror = not brush.brushMirror end
    if ui.itemHovered() then ui.setTooltip('Flip sticker (Z)') end
  end

  brush.brushSize = ui.slider('##brushSize', brush.brushSize * 100, 0.1, maxSize * 100, 'Size: %.1f cm', 2) / 100
  if ui.itemHovered() then ui.setTooltip('Use mouse wheel to quickly change size') end
  if ui.itemEdited() then selectedBrushOutlineDirty = true end

  if stored.hasPen then
    brush.penMinRadiusMult = ui.slider('##penMinRadiusMult', brush.penMinRadiusMult * 100, 0, 100, 'Minimum size: %.1f%%') / 100
    if ui.itemHovered() then ui.setTooltip('Size of a brush with minimum pen pressure') end
  end

  if stickerMode then
    ui.setNextItemWidth(ui.availableSpaceX() - 60)
    brush.brushAspectMult = ui.slider('##brushAspectMult', brush.brushAspectMult * 100, 4, 2500, 'Stretch: %.0f%%', 4) / 100
    if ui.itemHovered() then ui.setTooltip('Use mouse wheel and hold Ctrl to quickly change size') end
    if ui.itemEdited() then selectedBrushOutlineDirty = true end
    ui.sameLine(0, 4)
    if ui.button('Reset', vec2(56, 0)) then
      brush.brushAspectMult = 1
      selectedBrushOutlineDirty = true
    end
  end

  if not stickerMode and not noStepSize then
    brush.brushStepSize = ui.slider('##brushStepSize', brush.brushStepSize * 100, 0.1, 50, 'Step size: %.1f cm', 2) / 100
  end

  brush.brushAlpha = ui.slider('##alpha', brush.brushAlpha * 100, 0, 100, 'Opacity: %.1f%%') / 100
    if ui.itemHovered() then ui.setTooltip('Use digit buttons to quickly change opacity') end

  if ui.checkbox('##randomAngle', brush.brushRandomizedAngle) then brush.brushRandomizedAngle = not brush.brushRandomizedAngle end
  if ui.itemHovered() then ui.setTooltip('Randomize angle when drawing') end
  ui.sameLine(0, 4)
  ui.setNextItemWidth(210 - 22 - 4 - 60)
  brush.brushAngle = (brush.brushAngle % 360 + 360) % 360
  brush.brushAngle = ui.slider('##brushAngle', brush.brushAngle, 0, 360, 'Angle: %.0f°')
  if ui.itemHovered() then ui.setTooltip('Use mouse wheel and hold Alt to quickly change angle') end
  ui.sameLine(0, 4)
  if ui.button('Reset##angle', vec2(56, 0)) then
    brush.brushAngle = 0
  end

  if not stickerMode and not noStepSize then
    brush.smoothing = ui.slider('##smoothing', brush.smoothing * 100, 0, 100, 'Smoothing: %.1f%%') / 100
      if ui.itemHovered() then ui.setTooltip('Smoothing makes brush move smoother and slower') end
  end

  if not noSymmetry then
    if ui.checkbox('With symmetry', brush.withMirror) or shortcuts.toggleSymmetry() then brush.withMirror = not brush.withMirror end
    if ui.itemHovered() then ui.setTooltip('Paith with symmetry (Y)\nMirrors things from one side of a car to another') end
  end

  if ui.checkbox('Paint through', brush.paintThrough) or shortcuts.toggleDrawThrough() then brush.paintThrough = not brush.paintThrough end
  if ui.itemHovered() then ui.setTooltip('Paint through model (R)\nIf enabled, drawings would go through model and leave traces on the opposite side as well') end
end

local function BrushBlock(brush)
  if brush.brushTex == '' then brush.brushTex = brushes[1][2] end
  local anySelected = false
  ui.childWindow('brushesList', vec2(210, 60), false, bit.bor(ui.WindowFlags.HorizontalScrollbar, ui.WindowFlags.AlwaysHorizontalScrollbar, ui.WindowFlags.NoBackground), function ()
    ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
    for i = 1, #brushes do
      local selected = brushes[i][2] == brush.brushTex
      if ui.button('##'..i, 48, selected and ui.ButtonFlags.Active or ui.ButtonFlags.None) then 
        brush.brushTex = brushes[i][2]
        selectedBrushOutlineDirty = true
      end
      if selected then
        anySelected = true
      end
      ui.addIcon(brushes[i][2], 36, 0.5, nil, 0)
      if ui.itemHovered() then ui.setTooltip('Brush: '..brushes[i][1]) end
      ui.sameLine(0, 4)
    end
    ui.popStyleColor()
    ui.newLine()
  end)
  if not anySelected then
    brush.brushTex = brushes[1][2]
  end
  ui.itemPopup(function ()
    if ui.selectable('Open in Explorer') then
      os.openInExplorer(brushesDir)
    end
    if ui.selectable('Refresh') then
      rescanBrushes()
    end
  end)
end

local function fitMaskingPoints(fitFirst)
  if fitFirst then
    maskingDir = math.cross(maskingPoints[1] - maskingPoints[2], maskingPoints[4] - maskingPoints[3]):normalize()
    maskingPos = (maskingPoints[1] + maskingPoints[2]) / 2
    local ort1 = math.cross(maskingDir, vec3(1, 0, 0)):normalize()
    local ort2 = math.cross(maskingDir, vec3(0, 0, 1)):normalize()
    maskingPoints[3] = vec3(maskingPoints[3].x, maskingPos.y - maskingPos.z * ort1.y / ort1.z + ort2.y * maskingPoints[3].x / ort2.x, 0)
    maskingPoints[4] = vec3(maskingPoints[4].x, maskingPos.y - maskingPos.z * ort1.y / ort1.z + ort2.y * maskingPoints[4].x / ort2.x, 0)
  else
    maskingDir = math.cross(maskingPoints[1] - maskingPoints[2], maskingPoints[4] - maskingPoints[3]):normalize()
    maskingPos = (maskingPoints[3] + maskingPoints[4]) / 2
    local ort2 = math.cross(maskingDir, vec3(0, 0, 1)):normalize()
    local ort1 = math.cross(maskingDir, vec3(1, 0, 0)):normalize()
    maskingPoints[1] = vec3(0, maskingPos.y - maskingPos.x * ort2.y / ort2.x + ort1.y * maskingPoints[1].z / ort1.z, maskingPoints[1].z)
    maskingPoints[2] = vec3(0, maskingPos.y - maskingPos.x * ort2.y / ort2.x + ort1.y * maskingPoints[2].z / ort1.z, maskingPoints[2].z)
  end
end

local function applyQuickMasking(from, to)
  if math.abs(from.x - to.x) < math.abs(from.z - to.z) then
    maskingPoints[1] = vec3(0, from.y, from.z)
    maskingPoints[2] = vec3(0, to.y, to.z)
    maskingPoints[3] = vec3(-1, 0, 0)
    maskingPoints[4] = vec3(1, 0, 0)
    fitMaskingPoints(true)
  else
    maskingPoints[1] = vec3(0, 0, -1)
    maskingPoints[2] = vec3(0, 0, 1)
    maskingPoints[3] = vec3(from.x, from.y, 0)
    maskingPoints[4] = vec3(to.x, to.y, 0)
    fitMaskingPoints(false)
  end
end

local function getBrushUp(dir, tool)
  local brush = tool.brush
  return mat4x4.rotation(math.rad(brush.brushRandomizedAngle and tool.__brushRandomAngle or brush.brushAngle), dir):transformVector(car.up)
end

local fonts
local fontsDir = __dirname..'/fonts'
local function rescanFonts()
  fonts = {
    { name = 'Arial', source = 'Arial:@System' },
    { name = 'Bahnschrift', source = 'Bahnschrift:@System' },
    { name = 'Calibri', source = 'Calibri:@System' },
    { name = 'Comic Sans MS', source = 'Comic Sans MS:@System' },
    { name = 'Consolas', source = 'Consolas' },
    { name = 'Courier New', source = 'Courier New:@System' },
    { name = 'Impact', source = 'Impact:@System' },
    { name = 'Orbitron', source = 'Orbitron' },
    { name = 'Segoe UI', source = 'Segoe UI' },
    { name = 'Times New Roman', source = 'Times New Roman:@System' },
    { name = 'VCR OSD Mono', source = 'VCR OSD Mono' },
    { name = 'Webdings', source = 'Webdings:@System' },
  }
  for _, v in ipairs(io.scanDir(fontsDir, '*.ttf')) do
    table.insert(fonts, { name = v:sub(1, #v - 4), source = v:sub(1, #v - 4)..':'..__dirname..'/fonts' })
  end
  table.sort(fonts, function (a, b) return a.name < b.name end)
end

local tools = {
  {
    name = 'Brush (B)',
    key = shortcuts.toolBrush,
    icon = icons.Brush,
    ui = function (s)
      ui.header('Color:')
      ColorBlock()
      ui.offsetCursorY(20)
      ui.header('Brush:')
      BrushBlock(s.brush)
      BrushBaseBlock(s.brush, 0.5)
    end,
    brush = brushParams('brush'),
    brushColor = function(s) return rgbm.new(stored.color.rgb, s.brush.brushAlpha) end,
    brushSize = function (s) return vec2(s.brush.brushSize, s.brush.brushSize) end,
    -- blendMode = render.BlendMode.BlendAccurate,
  },
  {
    name = 'Eraser (E)',
    key = shortcuts.toolEraser,
    icon = icons.Eraser,
    ui = function (s)
      ui.header('Background color:')
      ColorBlock('bgColor')
      ui.offsetCursorY(20)
      ui.header('Eraser:')
      BrushBlock(s.brush)
      BrushBaseBlock(s.brush, 0.5)
    end,
    brush = brushParams('eraser'),
    brushColor = function(s) return stored.bgColor end,
    brushSize = function (s) return vec2(s.brush.brushSize, s.brush.brushSize) end,
  },
  {
    name = 'Stamp (S)',
    key = shortcuts.toolStamp,
    icon = icons.Stamp,
    ui = function (s)
      ui.header('Color:')
      ColorBlock()
      ui.offsetCursorY(20)

      ui.header('Stamp:')
      ui.combo('##set', string.format('Set: %s', selectedStickerSet.name), ui.ComboFlags.None, function ()
        for i = 1, #stickers do
          if ui.selectable(stickers[i].name, stickers[i] == selectedStickerSet) then
            selectedStickerSet = stickers[i]
            stored.selectedStickerSet = i
          end
        end
        if ui.selectable('New category…') then
          ui.modalPrompt('Create new category', 'Category name:', nil, function (value)
            if #value > 0 and io.createDir(decalsDir..'/'..value) then
              ui.toast(ui.Icons.Confirm, 'New category created: '..tostring(value))
              rescanStickers()
              selectedStickerSet = table.findFirst(stickers, function (item) return item.name == value end)
            else
              ui.toast(ui.Icons.Warning, 'Couldn’t create a new category: '..tostring(value))
            end
          end)
        end
      end)

      local items = selectedStickerSet.items
      if s.brush.brushTex == '' then s.brush.brushTex = items[1][2] end
      ui.childWindow('stickersList', vec2(210, 210), false, ui.WindowFlags.AlwaysVerticalScrollbar, function ()
        ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
        local itemSize = vec2(100, 60)
        for i = 1, #items do
          if ui.areaVisible(itemSize) then
            local size = ui.imageSize(items[i][2])
            if ui.button('##'..i, vec2(100, 60), s.brush.brushTex == items[i][2] and ui.ButtonFlags.Active or ui.ButtonFlags.None) then 
              s.brush.brushTex = items[i][2]
              selectedBrushOutlineDirty = true
            end
            local s = vec2(90, 90 * size.y / size.x)
            if s.y > 54 then s:scale(54 / s.y) end
            ui.addIcon(items[i][2], s, 0.5, nil, 0)
            if ui.itemHovered() then ui.setTooltip('Brush: '..items[i][1]) end
          else
            ui.dummy(itemSize)
          end
          if i % 2 == 1 then ui.sameLine(0, 0) end
        end
        ui.popStyleColor()
        ui.newLine()
      end)

      local _, i = table.findFirst(items, function (item, _, tex)
        return item[2] == tex
      end, s.brush.brushTex)
      i = i or 0

      if shortcuts.arrowRight() then
        s.brush.brushTex = items[i % #items + 1][2]
        selectedBrushOutlineDirty = true
      end

      if shortcuts.arrowDown() then
        s.brush.brushTex = items[(i + 1) % #items + 1][2]
        selectedBrushOutlineDirty = true
      end

      if shortcuts.arrowLeft() then
        s.brush.brushTex = items[(i - 2 + #items) % #items + 1][2]
        selectedBrushOutlineDirty = true
      end

      if shortcuts.arrowUp() then
        s.brush.brushTex = items[(i - 3 + #items) % #items + 1][2]
        selectedBrushOutlineDirty = true
      end

      if ui.itemHovered() then
        ui.setTooltip('Use arrow keys to quickly switch between items')
      end

      ui.itemPopup(function ()
        if ui.selectable('Add new decal…') then
          os.openFileDialog({
            title = 'Add new decal',
            defaultFolder = ac.getFolder(ac.FolderID.Root),
            fileTypes = { { name = 'Images', mask = '*.png' } },
            addAllFilesFileType = true,
            flags = bit.bor(os.DialogFlags.PathMustExist, os.DialogFlags.FileMustExist)
          }, function (err, filename)
            if filename then 
              local fileName = filename:gsub('.+[/\\\\]', '')
              if io.copyFile(filename, decalsDir..'/'..selectedStickerSet.name..'/'..fileName, true) then
                rescanStickers()
                selectedStickerSet = table.findFirst(stickers, function (item) return item.name == selectedStickerSet.name end)
                s.brush.brushTex = decalsDir..'/'..selectedStickerSet.name..'/'..fileName
                ui.toast(ui.Icons.Confirm, 'New decal added: '..fileName:sub(1, #fileName - 4))
                return
              end
            end
            if err or filename then
              ui.toast(ui.Icons.Warning, 'Couldn’t add a new decal: '..(err or 'unknown error'))
            end
          end)
        end
        if ui.selectable('Open in Explorer') then
          os.openInExplorer(decalsDir)
        end
        if ui.selectable('Refresh') then
          rescanStickers()
        end
      end)

      ui.alignTextToFramePadding()
      ui.text('Align sticker:')
      ui.sameLine()
      ui.setNextItemWidth(ui.availableSpaceX())
      stored.alignSticker = ui.combo('##alignSticker', stored.alignSticker, ui.ComboFlags.None, {
        'No',
        'Align to surface',
        'Fully align'
      })

      local brush = s.brush
      BrushBaseBlock(brush, 4, true)
    end,
    brush = brushParams('stamp', 0.2, 1),
    brushColor = function(s) return rgbm.new(stored.color.rgb, s.brush.brushAlpha) end,
    brushSize = function (s) 
      local size = ui.imageSize(s.brush.brushTex)
      return vec2(s.brush.brushSize, s.brush.brushSize * size.y / size.x)
    end,
    stickerMode = true,
    stickerContinious = false,
  },
  {
    name = 'Mirroring stamp (K)',
    key = shortcuts.toolMirroringStamp,
    icon = icons.MirroringStamp,
    ui = function (s)
      ui.header('Mirroring stamp:')
      BrushBlock(s.brush)
      BrushBaseBlock(s.brush, 0.5, false, true, true)
    end,
    brush = brushParams('mirroringStamp'),
    procBrushTex = function (s, ray, previewMode)
      if not s._shot then
        s._shot = ac.GeometryShot(selectedMeshes, 256):setShadersType(render.ShadersType.SampleColor)
        s._ksAmbient = selectedMeshes:getMaterialPropertyValue('ksAmbient')
      end
      local up = getBrushUp(ray.dir, s)
      selectedMeshes:setMaterialTexture('txDiffuse', editingCanvas)
      selectedMeshes:setMaterialProperty('ksAmbient', 1)
      s._shot:clear(table.random(rgbm.colors))
      local lpos, ldir, lup = car.worldToLocal:transformPoint(ray.pos), car.worldToLocal:transformVector(ray.dir), car.worldToLocal:transformVector(up)
      lpos.x, ldir.x, lup.x = -lpos.x, -ldir.x, -lup.x
      local ipos, idir, iup = car.bodyTransform:transformPoint(lpos), car.bodyTransform:transformVector(ldir), car.bodyTransform:transformVector(lup)
      local brushSize = previewMode and s.brush.brushSize or s.brush.brushSize * brushSizeMult(s.brush)
      s._shot:setOrthogonalParams(vec2(brushSize, brushSize), 100):update(ipos, idir, iup, 0)
      selectedMeshes:setMaterialTexture('txDiffuse', aoCanvas)
      selectedMeshes:setMaterialProperty('ksAmbient', s._ksAmbient)
      -- DebugTex = s._shot
      return s._shot
    end,
    procProjParams = function (s, pr)
      pr.mask2 = s.brush.brushTex
      pr.mask2Flags = render.TextureMaskFlags.UseAlpha
    end,
    brushColor = function(s) return rgbm(1, 1, 1, s.brush.brushAlpha) end,
    brushSize = function (s) return vec2(-s.brush.brushSize, s.brush.brushSize) end,
    stickerMode = true,
    stickerNoAlignment = true,
    stickerContinious = true
  },
  {
    name = 'Blur/Smudge (Alt+B)',
    key = shortcuts.toolBlurTool,
    icon = icons.BlurTool,
    ui = function (s)
      ui.header('Blur tool:')
      BrushBlock(s.brush)
      BrushBaseBlock(s.brush, 0.5, false, true, true)
      
      s.brush.blur = ui.slider('##blur', s.brush.blur * 1000, 0, 100, 'Blur: %.0f%%') / 1000
      s.brush.smudge = ui.slider('##smudge', s.brush.smudge * 100, 0, 100, 'Smudge: %.0f%%', 0.5) / 100

      ui.offsetCursorY(20)
      ui.header('Sharpness boost:')
      if ui.checkbox('Active', s.brush.sharpnessMode) then
        s.brush.sharpnessMode = not s.brush.sharpnessMode
      end
      s.brush.sharpness = ui.slider('##sharpness', s.brush.sharpness * 100, 0, 500, 'Intensity: %.0f%%', 2) / 100
      ui.textWrapped('Sharpness boost is some sort of an inverse to blur. Might help to increase local sharpness a bit or, with less well tuned settings, achieve some other strange effects.')
    end,
    brush = brushParams('blurTool', nil, nil, { blur = 0.01, smudge = 0, sharpnessMode = false, sharpness = 1.5 }),
    procBrushTex = function (s, ray, previewMode)
      if not s._shot then
        s._shot = ac.GeometryShot(selectedMeshes, 256):setShadersType(render.ShadersType.SampleColor)
        s._shotBlurred = ui.ExtraCanvas(vec2(128, 128))
        s._shotSharpened = ui.ExtraCanvas(vec2(128, 128))
        s._ksAmbient = selectedMeshes:getMaterialPropertyValue('ksAmbient')
      end
      if previewMode or not s._rayPos then
        s._rayPos = ray.pos:clone()
        s._rayDir = ray.dir:clone()
        if previewMode then return end
      else
        s._rayPos = math.applyLag(s._rayPos, ray.pos, s.brush.smudge, ac.getDeltaT())
        s._rayDir = math.applyLag(s._rayDir, ray.dir, s.brush.smudge, ac.getDeltaT()):normalize()
      end
      local up = getBrushUp(s._rayDir, s)
      selectedMeshes:setMaterialTexture('txDiffuse', editingCanvas)
      selectedMeshes:setMaterialProperty('ksAmbient', 1)
      s._shot:clear(table.random(rgbm.colors))
      local brushSize = s.brush.brushSize * brushSizeMult(s.brush)
      s._shot:setOrthogonalParams(vec2(brushSize, brushSize), 100):update(s._rayPos, s._rayDir, up, 0)
      selectedMeshes:setMaterialTexture('txDiffuse', aoCanvas)
      selectedMeshes:setMaterialProperty('ksAmbient', s._ksAmbient)
      if s.brush.blur <= 0.0001 then
        return s._shot
      end
      s._shotBlurred:clear(rgbm.colors.transparent):update(function (dt)
        ui.beginBlurring()
        ui.drawImage(s._shot, 0, 128)
        ui.endBlurring(s.brush.blur)
      end)
      if s.brush.sharpnessMode then
        s._shotSharpened:update(function (dt)
          ui.renderShader({
            p1 = vec2(0, 0),
            p2 = vec2(128, 128),
            blendMode = render.BlendMode.Opaque,
            textures = {
              txBlurred = s._shotBlurred,
              txBase = s._shot
            },
            values = {
              gIntensity = tonumber(s.brush.sharpness)
            },
            shader = [[float4 main(PS_IN pin) {
              float4 r = lerp(txBlurred.Sample(samLinear, pin.Tex), txBase.Sample(samLinear, pin.Tex), gIntensity);
              r.a = 1;
              return r;
            }]]
          })
        end)
        return s._shotSharpened
      end
      return s._shotBlurred
    end,
    procProjParams = function (s, pr)
      pr.mask2 = s.brush.brushTex
      pr.mask2Flags = render.TextureMaskFlags.UseAlpha
    end,
    brushColor = function(s) return rgbm(1, 1, 1, s.brush.brushAlpha) end,
    brushSize = function (s) return vec2(s.brush.brushSize, s.brush.brushSize) end,
    stickerMode = true,
    stickerNoAlignment = true,
    stickerContinious = true
  },
  {
    name = 'Text (T)',
    key = shortcuts.toolText,
    icon = icons.Text,
    ui = function (s)
      if fonts == nil then
        rescanFonts()
      end

      local selectedFont = table.findFirst(fonts, function (item, _, sf) return item.source == sf end, stored.selectedFont)
      if selectedFont == nil then
        selectedFont = fonts[1]
        stored.selectedFont = selectedFont.source
      end

      ui.header('Color:')
      ColorBlock()
      ui.offsetCursorY(20)

      ui.beginGroup()
      ui.header('Text:')
      s._labelText = ui.inputText('Text', s._labelText, ui.InputTextFlags.Placeholder)
      if ui.itemEdited() then s._labelDirty = true end

      ui.combo('##fonts', 'Font: '..tostring(selectedFont.name), ui.ComboFlags.None, function ()
        for i = 1, #fonts do
          if ui.selectable(fonts[i].name, fonts[i] == selectedFont) then
            selectedFont = fonts[i]
            stored.selectedFont, s._labelDirty = selectedFont.source, true
          end

          if ui.itemHovered() then
            ui.tooltip(function ()
              if s._previewCanvas ~= nil then
                s._previewCanvas:dispose()
              end
              
              local font = fonts[i].source
              if stored.fontBold then font = font..';Weight=Bold' end
              if stored.fontItalic then font = font..';Style=Italic' end
              ui.pushDWriteFont(font)
              local canvasSize = ui.measureDWriteText(s._labelText, 24)
              canvasSize.x, canvasSize.y = math.max(canvasSize.x, 24), canvasSize.y + 8
              s._previewCanvas = ui.ExtraCanvas(canvasSize):clear(rgbm.colors.transparent):update(function (dt)
                ui.dwriteTextAligned(s._labelText, 24, ui.Alignment.Center, ui.Alignment.Center, ui.availableSpace(), false, rgbm.colors.white)
              end)
              ui.popDWriteFont()
              ui.image(s._previewCanvas, canvasSize)
            end)
          end
        end
      end)
      ui.itemPopup(function ()
        if ui.selectable('Open in Explorer') then
          os.openInExplorer(fontsDir)
        end
        if ui.selectable('Refresh') then
          rescanFonts()
        end
      end)
      
      if ui.checkbox('Bold', stored.fontBold) then stored.fontBold, s._labelDirty = not stored.fontBold, true end
      if ui.checkbox('Italic', stored.fontItalic) then stored.fontItalic, s._labelDirty = not stored.fontItalic, true end
      ui.endGroup()

      if ui.itemHovered() and not s._labelDirty then
        ui.tooltip(function ()
          ui.image(s.brush.brushTex, ui.imageSize(s.brush.brushTex):scale(0.5))
        end)
      end

      -- local size = ui.imageSize(s.brush.brushTex)
      -- ui.drawImage(s.brush.brushTex, ui.getCursor(), ui.getCursor() + vec2(210, 210 * size.y / size.x))
      -- ui.offsetCursorY(math.ceil(210 * size.y / size.x / 20 + 0.5) * 20)

      ui.alignTextToFramePadding()
      ui.text('Align text:')
      ui.sameLine()
      ui.setNextItemWidth(ui.availableSpaceX())
      stored.alignSticker = ui.combo('##alignSticker', stored.alignSticker, ui.ComboFlags.None, {
        'No',
        'Align to surface',
        'Fully align'
      })

      local brush = s.brush
      BrushBaseBlock(brush, 4, true)
      
      if s._labelDirty then
        if s.brush.brushTex and type(s.brush.brushTex) ~= 'string' then
          s.brush.brushTex:dispose()
        end
        local font = selectedFont.source
        if stored.fontBold then font = font..';Weight=Bold' end
        if stored.fontItalic then font = font..';Style=Italic' end
        ui.pushDWriteFont(font)
        local canvasSize = ui.measureDWriteText(s._labelText, 48)
        canvasSize.x, canvasSize.y = math.max(canvasSize.x, 48), canvasSize.y + 16
        s.brush.brushTex = ui.ExtraCanvas(canvasSize):clear(rgbm.colors.transparent):update(function (dt)
          ui.dwriteTextAligned(s._labelText, 48, ui.Alignment.Center, ui.Alignment.Center, ui.availableSpace(), false, rgbm.colors.white)
        end)
        ui.popDWriteFont()
        s._labelDirty = false
      end
    end,
    brush = brushParams('text', 0.2, 1),
    brushColor = function(s) return rgbm.new(stored.color.rgb, s.brush.brushAlpha) end,
    brushSize = function (s) 
      local size = ui.imageSize(s.brush.brushTex)
      return vec2(s.brush.brushSize, s.brush.brushSize * size.y / size.x)
    end,
    stickerMode = true,
    stickerContinious = false,
    blendMode = render.BlendMode.BlendPremultiplied,
    _labelText = ac.getDriverName(0),
    _labelDirty = true
  },
  {
    name = 'Masking (M)',
    key = shortcuts.toolMasking,
    icon = icons.Masking,
    ui = function (s)
      -- if not maskingCarView then
      --   maskingCarView = ac.GeometryShot(selectedMeshes, vec2(210, 130)):setClippingPlanes(100, 1e5)
      --   selectedMeshes:setMaterialTexture('txDiffuse', maskingCanvas)
      --   maskingCarView:update(car.position + car.side * 1000, -car.side, car.up, 0.15)
      --   selectedMeshes:setMaterialTexture('txDiffuse', aoCanvas)
      -- end
      -- ui.drawImage(maskingCarView, ui.getCursor(), ui.getCursor() + vec2(210, 130))

      if ui.checkbox('Masking is active', maskingActive) then
        maskingActive = not maskingActive
      end
      if ui.itemHovered() then
        ui.setTooltip('Toggle masking (Ctrl+M)')
      end

      -- ui.textWrapped('Masking tool is a plane separating model in two halves. When you draw a thing, it would only get drawn on the side of a plane with camera. Might help in masking things quickly. For something more complex, use stencils.\n\nClick model and drag mouse to quickly create a new plane.')
      ui.textWrapped('Masking tool is a plane separating model in two halves. When you draw a thing, it would only get drawn on the side of a plane with camera. Might help in masking things quickly.\n\nClick model and drag mouse to quickly create a new plane.\n\nPro tip: when using brush, hold M for more than 0.2 seconds: tool will switch to masking temporary, so you can quickly put a mask and go back to brush by releasing M.')
    end,
    action = function (s)
      local ray = render.createMouseRay()
      local d = selectedMeshes:raycast(ray)
      if d ~= -1 then s._d = d end
      if d ~= -1 and uiState.isMouseLeftKeyClicked then
        maskingCreatingFrom = car.worldToLocal:transformPoint(ray.pos + ray.dir * d)
        s._moving = false
      elseif maskingCreatingFrom then
        if not uiState.isMouseLeftKeyDown then
          if s._moving then
            local endingPos = car.worldToLocal:transformPoint(ray.pos + ray.dir * d)
            applyQuickMasking(maskingCreatingFrom, endingPos)
            s._moving = false
          end
          maskingCreatingFrom, maskingCreatingTo = nil, nil
        end
        if not s._moving and #ui.mouseDragDelta() > 0 then
          addUndo(maskingBackup())
          s._moving = true
          maskingActive = true
        end
        if s._moving then
          maskingCreatingTo = car.worldToLocal:transformPoint(ray.pos + ray.dir * s._d)
        end
      end
    end,
  },
  {
    name = 'Eyedropper (I)',
    key = shortcuts.toolEyeDropper,
    icon = icons.EyeDropper,
    ui = function (s)
      ui.header('Color:')
      ColorBlock()
      ui.offsetCursorY(20)

      ui.header('Eyedropper:')
      ui.alignTextToFramePadding()
      ui.text('Sample size:')
      ui.sameLine()
      ui.setNextItemWidth(ui.availableSpaceX())
      stored.eyeDropperRange = ui.combo('##sampleSize', stored.eyeDropperRange, ui.ComboFlags.None, {
        'Point sample',
        '3 by 3 average',
        '5 by 5 average',
        '7 by 7 average',
        '9 by 9 average',
      })
      if s._color and not ui.mouseBusy() then
        ColorTooltip(s._color)
        if uiState.isMouseLeftKeyDown then
          stored.color = s._color
          s._changing = true
        elseif s._changing then
          s._changing = false
          palette.addToUserPalette(s._color)
        end
      end
    end,
    action = function (s)
      if accessibleData ~= nil then
        local ray = render.createMouseRay()
        local uv = vec2()
        if selectedMeshes:raycast(ray, false, nil, nil, uv) ~= -1 then
          uv.x = uv.x - math.floor(uv.x)
          uv.y = uv.y - math.floor(uv.y)
          local c = uv * accessibleData:size()
          local range = 1 + (stored.eyeDropperRange - 1) * 2
          local offset = -math.ceil(range / 2)
          local cx, cy = math.floor(c.x) + offset, math.floor(c.y) + offset
          local colorPick = rgbm()
          s._color:set(colorPick)
          for x = 1, range do
            for y = 1, range do
              s._color:add(accessibleData:colorTo(colorPick, cx + x, cy + y))
            end
          end
          s._color:scale(1 / (range * range))
        end
      end
    end,
    _color = rgbm(1, 1, 1, 1),
    _changing = false
  }
}

local activeTool = tools[stored.activeToolIndex]
local previousToolIndex = stored.activeToolIndex
local toolSwitched = 0

local function SkinEditor()
  DrawControl()
  if selectedMeshes == nil then return end
  ui.offsetCursorY(20)

  ui.header('Tools:')
  for i = 1, #tools do
    local v = tools[i]
    local s = activeTool == v and toolSwitched ~= 0 and ui.time() > toolSwitched + 0.2
    local bg = s and rgbm(0.5, 0.5, 0, 1) or activeTool == v and uiState.accentColor * rgbm(1, 1, 1, 0.5)
    if bg then ui.pushStyleColor(ui.StyleColor.Button, bg) end
    if IconButton(v.icon, v.name, activeTool == v) or v.key and v.key(false) then
      activeTool = v
      toolSwitched = v.key and tonumber(ui.time()) or 0
      previousToolIndex = stored.activeToolIndex
      stored.activeToolIndex = i
      selectedBrushOutlineDirty = true
    end
    if bg then ui.popStyleColor() end
    ui.sameLine(0, 4)
    if ui.availableSpaceX() < 12 then ui.newLine(4) end
  end
  if IconButton(icons.Camera, 'Orbit camera (Ctrl+Space)\nUse middle mouse button or hold space to rotate camera', stored.orbitCamera) or shortcuts.toggleOrbitCamera() then
    stored.orbitCamera = not stored.orbitCamera
  end
  ui.sameLine(0, 4)
  if ui.availableSpaceX() < 32 then ui.newLine(4) end
  if IconButton(icons.MirroringHelper, 'Project other side (Ctrl+E)\nProject other side on current side to make making things symmetrical easier', stored.projectOtherSide) or shortcuts.toggleProjectOtherSide() then
    stored.projectOtherSide = not stored.projectOtherSide
  end

  ui.offsetCursorY(20)

  if toolSwitched ~= 0 and not activeTool.key:down() then
    if ui.time() > toolSwitched + 0.2 then
      activeTool = tools[previousToolIndex]
      toolSwitched = 0
      stored.activeToolIndex = previousToolIndex
      selectedBrushOutlineDirty = true
    else
      toolSwitched = 0
    end
  end

  if shortcuts.toggleMasking() then
    maskingActive = not maskingActive
  end

  ui.pushID(activeTool.name)
  ui.pushFont(ui.Font.Small)
  activeTool:ui()
  ui.popFont()
  ui.popID()
end

local pdistance, pnormal, pdir = 1, vec3(), vec3(1, 0, 0)

local function projectBrushTexture(tex, pos, dir, color, distance, previewMode, doNotUseToolProjParams)
  local brush = activeTool.brush
  if not brush then return end

  if activeTool.stickerMode and not activeTool.stickerNoAlignment and stored.alignSticker > 1 then
    local d, m = selectedMeshes:raycast(render.createRay(pos, dir), true, nil, pnormal)
    if d ~= -1 then
      pdir = m:getWorldTransformationRaw():transformVector(pnormal):scale(-1)
      pdistance = d
    else
      d = pdistance
    end
    pos = pos + dir * d
    dir = pdir:clone()
    if stored.alignSticker == 3 then
      dir = dir - car.up * dir:dot(car.up)
    end
    distance = 0.2
  end

  local size = activeTool:brushSize()
  if not previewMode and (not activeTool.stickerMode or activeTool.stickerContinious) then size = size * brushSizeMult(brush) end
  if brush.brushAspectMult > 1 then size.x = size.x * brush.brushAspectMult
  else size.y = size.y / brush.brushAspectMult end
  if brush.brushMirror then
    size.x = -size.x
  end
  if not activeTool.__brushRandomAngle or previewMode then
    activeTool.__brushRandomAngle = activeTool.brush.brushAngle
  else
    activeTool.__brushRandomAngle = math.random() * 360
  end
  local up = getBrushUp(dir, activeTool)
  local pr = {
    filename = tex,
    pos = pos,
    look = dir,
    up = up,
    color = color,
    size = size,
    depth =  brush.paintThrough and 1e9 or distance,
    doubleSided = brush.paintThrough,
    mask1 = maskingCanvas,
    mask1Flags = bit.bor(render.TextureMaskFlags.AltUV, render.TextureMaskFlags.Default),
    blendMode = not previewMode and activeTool.blendMode or nil
  }
  if activeTool.procProjParams and not doNotUseToolProjParams then activeTool:procProjParams(pr) end
  selectedMeshes:projectTexture(pr)
  if brush.withMirror then
    local lpos, ldir, lup = car.worldToLocal:transformPoint(pos), car.worldToLocal:transformVector(dir), car.worldToLocal:transformVector(up)
    lpos.x, ldir.x, lup.x = -lpos.x, -ldir.x, -lup.x
    pr.pos, pr.look, pr.up = car.bodyTransform:transformPoint(lpos), car.bodyTransform:transformVector(ldir), car.bodyTransform:transformVector(lup)
    pr.size.x = -pr.size.x
    selectedMeshes:projectTexture(pr)
  end
end

local function updateBrushOutline(stickerMode)
  if not selectedBrushOutline then
    selectedBrushOutline = ui.ExtraCanvas(vec2(128, 128), 4)
  end
  selectedBrushOutlineDirty = false
  if not activeTool.brush or stickerMode then
    selectedBrushOutline:clear(rgbm.colors.transparent)
    return
  end
  -- prepare brush outline in two stages: first, boost alpha and draw brush in white and draw it
  -- again in black and smaller to get a black and white mask, and then draw that mask with different
  -- shading params to turn black and white mask into transparency
  selectedBrushOutline:clear(rgbm.colors.black)
  selectedBrushOutline:update(function (dt)
    ui.renderShader({
      p1 = vec2(0, 0),
      p2 = vec2(128, 128),
      blendMode = render.BlendMode.Opaque,
      textures = {
        txBrush = activeTool.brush.brushTex
      },
      values = {
        gMargin = (0.5/128) / activeTool.brush.brushSize
      },
      shader = [[float4 main(PS_IN pin) {
        float tx = txBrush.Sample(samLinearBorder0, pin.Tex + float2(gMargin, gMargin)).w
          + txBrush.Sample(samLinearBorder0, pin.Tex + float2(gMargin, -gMargin)).w
          + txBrush.Sample(samLinearBorder0, pin.Tex + float2(-gMargin, gMargin)).w
          + txBrush.Sample(samLinearBorder0, pin.Tex + float2(-gMargin, -gMargin)).w;
        tx = saturate(tx * 20 - 1);
        tx *= 1 - saturate(txBrush.Sample(samLinear, pin.Tex).w * 20 - 1);
        return float4(1, 1, 1, tx);
      }]]
    })
  end)
end

local otherSideShot ---@type ac.GeometryShot
local otherSidePhase = -1
local otherSideSide = 0
local bakKsAmbient

local function updateAOCanvas()
  if aoCanvas == nil then return end

  local projectDir
  if stored.projectOtherSide then
    if not otherSideShot then
      bakKsAmbient = selectedMeshes:getMaterialPropertyValue('ksAmbient')
      otherSideShot = ac.GeometryShot(selectedMeshes, 2048):setOrthogonalParams(vec2(6, 4), 10):setClippingPlanes(-10, 0):setShadersType(render.ShadersType.SampleColor)
    end

    projectDir = car.side
    local s = math.sign(projectDir:dot(ac.getCameraForward()))
    if s > 0 then projectDir = -projectDir end
    if s ~= otherSideSide then otherSidePhase, otherSideSide = -1, s end

    if otherSidePhase ~= editingCanvasPhase then
      otherSidePhase = editingCanvasPhase
      selectedMeshes:setMaterialTexture('txDiffuse', editingCanvas)
      selectedMeshes:setMaterialProperty('ksAmbient', 1)
      otherSideShot:update(car.position, projectDir, car.up, 0)
      selectedMeshes:setMaterialTexture('txDiffuse', aoCanvas)
      selectedMeshes:setMaterialProperty('ksAmbient', bakKsAmbient)
    end
  end

  local ray, tex
  ray = render.createMouseRay()
  if activeTool.stickerMode then
    if activeTool.procBrushTex then tex = activeTool:procBrushTex(ray, true)
    else tex = activeTool.brush.brushTex end
  end

  if selectedBrushOutlineDirty then
    updateBrushOutline(activeTool.stickerMode and tex ~= nil)
  end
  
  aoCanvas:update(function (dt)
    drawWithAO(editingCanvas, aoTexture or carTexture)

    if stored.projectOtherSide then
      selectedMeshes:projectTexture({
        filename = otherSideShot,
        pos = car.position,
        look = -projectDir,
        up = car.up,
        color = rgbm(1, 1, 1, 0.1),
        size = vec2(-6, 4),
        depth = 1e9,
        doubleSided = false
      })
    end

    if tex then
      projectBrushTexture(tex, ray.pos, ray.dir, activeTool:brushColor() * rgbm(1, 1, 1, 0.3), nil, true)
    else
      projectBrushTexture(selectedBrushOutline, ray.pos, ray.dir, rgbm.colors.gray, nil, true, activeTool.stickerMode)
    end
  end)
end

local maskingDirty = true

local function updateMaskingCanvas()
  if not maskingActive then
    if maskingCanvas and maskingDirty then
      maskingDirty = false
      maskingCanvas:clear(rgbm.colors.white)
    end
    return
  end

  if not maskingCanvas then
    maskingCanvas = ui.ExtraCanvas(vec2(2048, 2048))
  end

  maskingDirty = true
  maskingCanvas:clear(rgbm.colors.black)
  maskingCanvas:update(function (dt)
    local mdir = maskingDir
    if mdir:dot(car.worldToLocal:transformPoint(ac.getCameraPosition()) - maskingPos) < 0 then mdir = mdir:clone():scale(-1) end
    local pos = maskingPos + mdir * 5
    local dir = math.cross(mdir, vec3(0, 0, 1))
    selectedMeshes:projectTexture({
      filename = 'color::#ffffff',
      pos = car.bodyTransform:transformPoint(pos),
      look = car.bodyTransform:transformVector(dir),
      up = car.bodyTransform:transformVector(mdir),
      color = rgbm.colors.white,
      size = vec2(10, 10),
      depth = 1e9,
      doubleSided = true
    })
  end)
end

local function cameraUpdate()
  if editingCanvas == nil then
    editingCanvas = ui.ExtraCanvas(vec2(2048, 2048)):clear(rgbm.new(stored.bgColor.rgb, 1))
    aoCanvas = ui.ExtraCanvas(vec2(2048, 2048), 4, render.AntialiasingMode.CMAA)
    selectedMeshes:setMaterialTexture('txDiffuse', aoCanvas)
  end

  if camera then
    local mat = mat4x4.rotation(cameraAngle.y, vec3(1, 0, 0)):mul(mat4x4.rotation(cameraAngle.x, vec3(0, 1, 0))):mul(car.bodyTransform)
    camera.transform.position = mat:transformPoint(vec3(0, car.aabbCenter.y * math.smoothstep(math.lerpInvSat(cameraAngle.y, 0.5, 0)), -8))
    camera.transform.look = mat:transformVector(vec3(0, 0, 1))
    camera.transform.up = mat:transformVector(vec3(0, 1, 0))
    camera.fov = 24

    camera.ownShare = math.applyLag(camera.ownShare, stored.orbitCamera and 1 or 0, 0.85, ac.getDeltaT())
    if stored.orbitCamera and (ui.keyboardButtonDown(ui.KeyIndex.Space) or ui.mouseDown(ui.MouseButton.Middle)) then
      cameraAngle:add(uiState.mouseDelta * vec2(-0.003, 0.003))
    end
    if not stored.orbitCamera and camera.ownShare < 0.001 then
      camera:dispose()
      camera = nil
    end
  elseif stored.orbitCamera then
    camera = ac.grabCamera('Paintshop')
    if camera then camera.ownShare = 0 end
  end
end

local smoothRayDir

local function paintUpdate()
  if activeTool.brush then
    if uiState.isMouseLeftKeyDown then
      if drawing then
        local ray = render.createMouseRay()
        local brush = activeTool.brush
        local tex = activeTool.procBrushTex and activeTool:procBrushTex(ray, false) or brush.brushTex
        editingCanvas:update(function ()
          local lastBrushDistance = brushDistance
          local hitDistance = selectedMeshes:raycast(ray)
          if hitDistance ~= -1 then brushDistance = hitDistance end
          if activeTool.stickerMode then
            projectBrushTexture(tex, ray.pos, ray.dir, activeTool:brushColor(), brushDistance)
            if not activeTool.stickerContinious then
              setTimeout(updateAccessibleData) -- projection happens a bit later, so updating data should also be delayed
              drawing = false
              selectedMeshes:setMotionStencil(taaFix.Off)
              ignoreMousePress = true
            end
            return
          elseif lastRay then
            local color = activeTool:brushColor()

            if brush.smoothing > 0 then
              smoothRayDir = math.applyLag(smoothRayDir, ray.dir, brush.smoothing ^ 0.3 * 0.9, 0.02)
              ray.dir:set(smoothRayDir)
            end

            local distance = ray.pos:clone():addScaled(ray.dir, brushDistance):distance(lastRay.pos:clone():addScaled(lastRay.dir, lastBrushDistance))
            if distance > brush.brushStepSize then
              local steps = math.min(100, math.floor(0.5 + distance / brush.brushStepSize))
              for i = 1, steps do
                local p = math.lerp(lastRay.pos, ray.pos, i / steps)
                local d = math.lerp(lastRay.dir, ray.dir, i / steps)
                projectBrushTexture(tex, p, d, color, math.lerp(lastBrushDistance, brushDistance, i / steps))
              end
              lastRay = ray
            end
          else
            projectBrushTexture(tex, ray.pos, ray.dir, activeTool:brushColor(), brushDistance)
            lastRay = ray
          end
          smoothRayDir = ray.dir:clone()
        end)
      elseif not ignoreMousePress then
        ignoreMousePress = ui.mouseBusy()
        if not ignoreMousePress then
          drawing = true
          selectedMeshes:setMotionStencil(taaFix.On)
          if not uiState.shiftDown then
            lastRay = nil
          end
          setTimeout(function ()
            -- adding undo in the next frame, so that dragging mask could cancel drawing operation
            if drawing then
              addUndo(editingCanvas:backup())
            end
          end)
        end
      end
    else
      if drawing then
        updateAccessibleData()
        selectedMeshes:setMotionStencil(taaFix.Off)
        drawing = false
      end
      ignoreMousePress = false
    end
  elseif activeTool.action then
    activeTool:action()
  end
  
  updateMaskingCanvas()
  updateAOCanvas()
end

function script.update(dt)
  if not appVisible then
    if camera then
      camera:dispose()
      camera = nil
    end
    return
  end
  if selectedMeshes ~= nil then
    cameraUpdate()
  end
end

function script.onWorldUpdate(dt)
  if appVisible and selectedMeshes ~= nil then
    ui.setAsynchronousImagesLoading(false)  -- when painting, easier to not wait for async images to load
    paintUpdate()
  end
end

local function rayPlane(ray, opposite)
  local s = opposite and car.look or car.side
  return ray:plane(car.position, s)
end

local maskingStartMousePos

---@param ray ray
local function draggingPoint(index, point, ray)
  local pos = car.bodyTransform:transformPoint(point)
  local hovered = ray:sphere(pos, 0.04) ~= -1
  render.circle(pos, -ac.getCameraForward(), 0.04,
    rgbm(hovered and sim.whiteReferencePoint or 0, sim.whiteReferencePoint, sim.whiteReferencePoint, 0.3), 
    rgbm(0, sim.whiteReferencePoint, sim.whiteReferencePoint, 1))
  if maskingDragging == 0 and uiState.isMouseLeftKeyClicked and hovered then
    maskingStartMousePos = ui.projectPoint(pos)
    maskingDragging = index
    ignoreMousePress = true
    drawing = false
    maskingCreatingFrom = nil
    addUndo(maskingBackup())
  elseif maskingDragging == index then
    maskingStartMousePos:add(uiState.mouseDelta)
    local r = render.createPointRay(maskingStartMousePos)
    local d = rayPlane(r, index > 2)
    if d ~= -1 then
      point:set(car.worldToLocal:transformPoint(r.pos + r.dir * d))
    end
  end
end

function script.draw3D()
  if appVisible and selectedMeshes ~= nil and maskingActive then
    if maskingCreatingFrom ~= nil and maskingCreatingTo ~= nil then
      applyQuickMasking(maskingCreatingFrom, maskingCreatingTo)
      render.circle(car.bodyTransform:transformPoint(maskingPos), car.bodyTransform:transformVector(maskingDir), 3,
        rgbm(sim.whiteReferencePoint, 0, 0, 0.1))
      return
    end

    render.circle(car.bodyTransform:transformPoint(maskingPos), car.bodyTransform:transformVector(maskingDir), 3,
      rgbm(sim.whiteReferencePoint, 0, 0, 0.3))

    local ray = render.createMouseRay()
    if not ui.mouseDown() then maskingDragging = 0 end
    render.setDepthMode(render.DepthMode.Off)
    draggingPoint(1, maskingPoints[1], ray)
    draggingPoint(2, maskingPoints[2], ray)
    draggingPoint(3, maskingPoints[3], ray)
    draggingPoint(4, maskingPoints[4], ray)

    if maskingDragging == 1 or maskingDragging == 2 then
      fitMaskingPoints(true)
    elseif maskingDragging == 3 or maskingDragging == 4 then
      fitMaskingPoints(false)
    end
  end
end

function script.windowMain(dt)
  if brushes == nil then
    rescanBrushes()
    rescanStickers()
  end
  
  ui.pushItemWidth(210)
  ui.setAsynchronousImagesLoading(true)
  if selectedMeshes == nil then
    MeshSelection()
  else
    SkinEditor()
  end
  ui.popItemWidth()

  if DebugTex then
    ui.setShadingOffset(1, 0, 1, 1)
    ui.image(DebugTex, 210, rgbm.colors.white, rgbm.colors.red)
    ui.resetShadingOffset()
  end
end

DebugTex = nil

function script.onShowWindowMain()
  appVisible = true
end

function script.onHideWindowMain()
  appVisible = false
  if selectedMeshes == nil then
    setTimeout(ac.unloadApp, 1)
  end
end

# Cooking-Sim

簡單料理模擬，透過拖曳與互動完成一碗麵。

## 玩法目標

- 依流程準備食材並完成一碗麵。
- 使用拖曳、互動與機器完成加工與組裝。

## 操作

- W/A/S/D：移動
- 左鍵：互動；對可拖曳物件左鍵拿起/放下
- E：互動（依提示）
- 滾輪：拖曳時調整距離
- 可互動/可拖曳物件會高亮提示

## 料理流程

1. 碗：找到碗並放到桌上。
2. 蔥：拿刀，刀尖碰觸切碎後放入碗。
3. 麵團：靠近麵條機互動變成麵條，切碎後放入碗。
4. 豬肉：刀尖切片，放到瓦斯爐開火烹調約 5 秒後放入碗。
5. 海苔：放入碗。
6. 蛋：刀尖切片後放入碗。
7. 湯：拿起湯匙，與鍋子互動取得湯後放入碗。

## 系統概覽

- 系統入口：`src/ServerScriptService/Loader.server.lua`
- 拖曳系統：`src/StarterPlayer/StarterCharacterScripts/DragSystem.client.lua`
- 互動高亮：`src/StarterPlayer/StarterCharacterScripts/ClickDetectorHighlight.client.lua`
- 第一人稱鎖定：`src/StarterPlayer/StarterCharacterScripts/FirstPerson.client.lua`
- 角色狀態限制：`src/StarterPlayer/StarterCharacterScripts/DisableState.client.lua`
- 伺服器拖曳權限：`src/ServerScriptService/Systems/DragHandler/init.lua`
- 物件模組載入：`src/ServerScriptService/Systems/ObjectsHandler/init.lua`
- 麵條機：`src/ServerScriptService/Systems/ObjectsHandler/Modules/NoodleMachine.lua`
- NPC 系統：`src/ServerScriptService/Systems/NPCHandler/init.lua`
- 碰撞群組：`src/ServerScriptService/Systems/CollisionHandler/init.lua`

## 專案結構

- `src/ServerScriptService/Systems`：伺服器系統（拖曳、NPC、物件、碰撞）。
- `src/StarterPlayer/StarterCharacterScripts`：玩家端腳本（拖曳、高亮）。
- `default.project.json`：Rojo 專案設定檔（若使用 Rojo）。

## 場景與資源需求

- `ReplicatedStorage/DragRequest`（RemoteFunction）與 `ReplicatedStorage/ForcePickup`（RemoteEvent）。
- `ReplicatedStorage/Ingredients`：食材模型來源。
- `ReplicatedStorage/NPCs/Rig`：NPC 生成用的 Rig。
- `ServerScriptService/Bindables/GetDraggingObject`、`ReleaseDraggingObject`（BindableFunction）。
- `Workspace/NPCSystem/NPCSpawn`、`Workspace/NPCSystem/Tables`（含 `Seats` 與 `Hitbox`）。
- `Workspace/SpawnedObjects`：動態生成物件的容器。
- `Workspace/Terrain/DragTarget`（Attachment）：拖曳目標點。
- 碰撞群組：`Player`/`NPC`/`Draggable`/`Default`（於 PhysicsService 設定）。

## 場景節點結構（參考）

```text
Workspace
- NPCSystem
  - NPCSpawn (Part)
  - Tables
    - TableModel
      - Hitbox (Part)
      - Seats (Folder -> BaseParts)
- SpawnedObjects (Folder)
- Terrain
  - DragTarget (Attachment)
ReplicatedStorage
- Ingredients (Folder)
- NPCs (Folder)
  - Rig (Model)
- DragRequest (RemoteFunction)
- ForcePickup (RemoteEvent)
ServerScriptService
- Bindables
  - GetDraggingObject (BindableFunction)
  - ReleaseDraggingObject (BindableFunction)
```

## 物件模組與標籤（CollectionService）

- 物件系統依照「標籤名稱 = 模組檔名」自動載入；標籤掛在對應的 Model/Part 上。
- `SpawnObject`：點擊後生成食材（需 `SpawnObject` 屬性）。
- `Knife`：刀刃觸碰切割（拖曳中才生效）。
- `NoodleMachine`：麵團轉麵條。
- `GasStove`：開關爐火（需 `CookerFire` 子物件）。
- `Pot`：偵測鍋內食材與熱源（使用 `Ingredients` 與 `StoveSlot` tag）。
- `Pork`：依 `CookTime` 與熱源更新熟度。
- `SoupPot`：拖曳湯互動啟用 `Active`。
- `SoupSpoon`：依 `Active` 切換 `Below/Top` 顯示。
- `Ramen`：組合碗內食材、完成後設 `Completed`，NPC 會判斷供餐。
- 其他使用的標籤：`Draggable`（可拖曳）、`Ingredients`（鍋內食材）、`StoveSlot`（爐火感應區）。

## 重要屬性（Attributes）

- `BeingDragged`：拖曳中狀態（拖曳系統寫入）。
- `SpawnObject`：生成食材的模型名稱。
- `IngredientType`：食材識別鍵（預設用模型名稱）。
- `RequiredIngredients` / `Completed`：拉麵碗需求與完成狀態。
- `CookTime` / `CookState` / `InPot` / `HasHeat`：烹調流程狀態。
- `Active`：湯與湯勺顯示狀態；座位也使用 `Active` 表示占用。
- `isOn`：瓦斯爐開關狀態。

## 開發與同步（可選）

- 本專案提供 `default.project.json` 供 Rojo 使用。
- 安裝工具（擇一）：`aftman install` 或 `rokit install`。
- 啟動同步：`rojo serve --project default.project.json`，再用 Studio 的 Rojo 插件連線。

## 常見問題 / 排錯

- NPC 出現 `Path compute failed (enter)`：確認 `NPCSpawn/Hitbox` 不被碰撞包住，目標點要在可走的地面上。
- 拖曳無法抓取：物件需加上 `Draggable` tag，且 `DragRequest/ForcePickup` 與 `DragTarget` 必須存在。
- 食材無法生成：生成點需有 `SpawnObject` 屬性，且 `ReplicatedStorage/Ingredients` 內有對應模型。
- 瓦斯爐不加熱或肉不熟：確認 `StoveSlot` tag、爐火已開啟，鍋子在感應範圍內。
- 碗無法完成：`Ramen` 需有 `Ramen` tag，食材 `IngredientType` 對應，完成後會設 `Completed`。

## 導入 Roblox Studio

1. 到 GitHub Releases 下載：`https://github.com/alaner652/114-VR-Project-Group-07/releases/tag/demo`。
2. 在 Assets 下載 `VR RAMEN SHOP.zip`，並解壓縮。
3. 若已安裝 Roblox Studio，直接雙擊解壓後的 `.rbxl` 即可開啟。
4. 或在 Studio 內使用 `File > Open` 開啟 `.rbxl`。
5. 若是 `.rbxm`：使用 `Model > Insert From File` 匯入。

## 查看原始碼

- GitHub：進入專案頁面，切到 `Code` 分頁即可瀏覽；需要下載可用 `Download ZIP` 或 `git clone https://github.com/alaner652/114-VR-Project-Group-07`。
- 本機：直接打開專案資料夾的 `src` 目錄即可查看所有腳本。
- Roblox Studio：匯入檔案後，在 Explorer 展開 `ServerScriptService`、`StarterPlayer` 等節點查看腳本。

## Demo

- https://www.roblox.com/games/108007882125822/VR-RAMEN-SHOP
- https://youtu.be/gYcwkoDgL_g（試玩與教學影片）
- 進入連結後點擊「遊玩」。
- 若未安裝 Roblox Player，依提示安裝即可。

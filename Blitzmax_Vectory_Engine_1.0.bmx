' Moteur 3D filaire en BlitzMax avec gestion de la caméra, chargement de fichiers .obj et collisions
' By Creepy Cat (C) 2025/2026 (https://github.com/BlackCreepyCat)

' Importer les modules nécessaires
Import brl.max2d
Import brl.filesystem
Import brl.linkedlist
Import brl.map

' Type pour un point 3D
Type TPoint3D
Field x:Float, y:Float, z:Float
Field r:Int, g:Int, b:Int, a:Int ' Couleurs RGBA pour compatibilité avec .obj
End Type

' Type pour un point 2D
Type TPoint2D
Field x:Float, y:Float
End Type

' Type pour une matrice 3x3 (pour les rotations)
Type TMatrix3x3
Field m:Float[3, 3]
End Type

' Type pour une caméra
Type TCamera
Field position:TPoint3D ' Position de la caméra
Field Rotation:TMatrix3x3 ' Matrice de rotation
Field focalLength:Float ' Distance focale pour la projection
Field viewportWidth:Int ' Largeur de la fenêtre
Field viewportHeight:Int ' Hauteur de la fenêtre
Field collisionType:Int ' Type de collision
Field radius:Float ' Rayon pour collision sphère
Field sphereOffset:TPoint3D ' Décalage du centre de la sphère de collision

Function Create:TCamera()
Local cam:TCamera = New TCamera
cam.position = New TPoint3D
cam.Rotation = RotationMatrixY(0)
cam.focalLength = 500
cam.collisionType = 0
cam.radius = 0
cam.sphereOffset = New TPoint3D
Return cam
End Function
End Type

' Type pour un objet 3D
Type TObject3D
Field vertices:TPoint3D[] ' Sommets de l'objet
Field edges:Int[,] ' Arêtes (paires de sommets)
Field position:TPoint3D ' Position de l'objet
Field Rotation:TMatrix3x3 ' Rotation de l'objet
Field Scale:TPoint3D ' Échelle de l'objet
Field collisionType:Int ' Type de collision (0 = aucun, 1 = joueur, 3 = objet)
Field radius:Float ' Rayon pour collision sphère
Field obbCenter:TPoint3D ' Centre de l'OBB (relatif à position)
Field obbExtents:TPoint3D ' Demi-dimensions de l'OBB (fixées par EntityBox)
Field obbAxes:TMatrix3x3 ' Axes locaux de l'OBB (matrice de rotation)
Field triangles:Int[,] ' Triangles pour collision triangle [v1, v2, v3]
Field lineColor:Int ' Couleur des lignes (ARGB)
Field sphereOffset:TPoint3D ' Décalage du centre de la sphère de collision

Function Create:TObject3D()
Local obj:TObject3D = New TObject3D
obj.position = New TPoint3D
obj.Rotation = RotationMatrixY(0)
obj.Scale = New TPoint3D
obj.Scale.x = 1; obj.Scale.y = 1; obj.Scale.z = 1
obj.collisionType = 0
obj.radius = 0
obj.obbCenter = New TPoint3D
obj.obbExtents = New TPoint3D
obj.obbAxes = RotationMatrixY(0)
obj.lineColor = $FF00FF00
obj.sphereOffset = New TPoint3D
Return obj
End Function

Method UpdateOBB()
obbAxes = Rotation
End Method
End Type

' Type pour une règle de collision
Type TCollision
Field srcType:Int ' Type source (ex: 1 = joueur)
Field dstType:Int ' Type destination (ex: 3 = objet)
Field collisionMethod:Int ' 1 = sphère-sphère, 2 = sphère-triangle, 3 = sphère-OBB
Field response:Int ' 0 = rien, 1 = arrêter, 2 = glisser
End Type

' Liste globale des règles de collision
Global collisionRules:TList = New TList

' Liste globale des entités pour collisions (TObject3D ou TCamera)
Global collisionEntities:TList = New TList

' Fonction pour multiplier une matrice 3x3 par un point
Function TransformPoint:TPoint3D(matrix:TMatrix3x3, point:TPoint3D)
Local result:TPoint3D = New TPoint3D
result.x = matrix.m[0, 0] * point.x + matrix.m[0, 1] * point.y + matrix.m[0, 2] * point.z
result.y = matrix.m[1, 0] * point.x + matrix.m[1, 1] * point.y + matrix.m[1, 2] * point.z
result.z = matrix.m[2, 0] * point.x + matrix.m[2, 1] * point.y + matrix.m[2, 2] * point.z
result.r = point.r; result.g = point.g; result.b = point.b; result.a = point.a
Return result
End Function

' Fonction pour translater un point
Function TranslatePoint:TPoint3D(point:TPoint3D, offset:TPoint3D)
Local result:TPoint3D = New TPoint3D
result.x = point.x + offset.x
result.y = point.y + offset.y
result.z = point.z + offset.z
result.r = point.r; result.g = point.g; result.b = point.b; result.a = point.a
Return result
End Function

' Fonction pour obtenir le centre de la sphère de collision
Function GetSphereCenter:TPoint3D(entity:Object)
Local center:TPoint3D = New TPoint3D
If TObject3D(entity)
Local obj:TObject3D = TObject3D(entity)
center = TranslatePoint(obj.position, TransformPoint(obj.Rotation, obj.sphereOffset))
ElseIf TCamera(entity)
Local cam:TCamera = TCamera(entity)
center = TranslatePoint(cam.position, TransformPoint(cam.Rotation, cam.sphereOffset))
EndIf
Return center
End Function

' Fonction pour projeter un point 3D en 2D
Function ProjectPoint:TPoint2D(point:TPoint3D, camera:TCamera)
Local result:TPoint2D = New TPoint2D
If point.z > 0.1
Local factor:Float = camera.focalLength / point.z
result.x = point.x * factor + camera.viewportWidth / 2
result.y = -point.y * factor + camera.viewportHeight / 2
Else
result = Null
EndIf
Return result
End Function

' Fonction pour transformer un point en espace caméra
Function TransformToCameraSpace:TPoint3D(point:TPoint3D, camera:TCamera)
Local offset:TPoint3D = New TPoint3D
offset.x = -camera.position.x
offset.y = -camera.position.y
offset.z = -camera.position.z
Local translated:TPoint3D = TranslatePoint(point, offset)
Local rotated:TPoint3D = TransformPoint(camera.Rotation, translated)
Return rotated
End Function

' Crée une matrice de rotation autour de l'axe X
Function RotationMatrixX:TMatrix3x3(angle:Float)
Local matrix:TMatrix3x3 = New TMatrix3x3
Local c:Float = Cos(angle), s:Float = Sin(angle)
matrix.m[0, 0] = 1; matrix.m[0, 1] = 0; matrix.m[0, 2] = 0
matrix.m[1, 0] = 0; matrix.m[1, 1] = c; matrix.m[1, 2] = -s
matrix.m[2, 0] = 0; matrix.m[2, 1] = s; matrix.m[2, 2] = c
Return matrix
End Function

' Crée une matrice de rotation autour de l'axe Y
Function RotationMatrixY:TMatrix3x3(angle:Float)
Local matrix:TMatrix3x3 = New TMatrix3x3
Local c:Float = Cos(angle), s:Float = Sin(angle)
matrix.m[0, 0] = c; matrix.m[0, 1] = 0; matrix.m[0, 2] = s
matrix.m[1, 0] = 0; matrix.m[1, 1] = 1; matrix.m[1, 2] = 0
matrix.m[2, 0] = -s; matrix.m[2, 1] = 0; matrix.m[2, 2] = c
Return matrix
End Function

' Crée une matrice de rotation autour de l'axe Z
Function RotationMatrixZ:TMatrix3x3(angle:Float)
Local matrix:TMatrix3x3 = New TMatrix3x3
Local c:Float = Cos(angle), s:Float = Sin(angle)
matrix.m[0, 0] = c; matrix.m[0, 1] = -s; matrix.m[0, 2] = 0
matrix.m[1, 0] = s; matrix.m[1, 1] = c; matrix.m[1, 2] = 0
matrix.m[2, 0] = 0; matrix.m[2, 1] = 0; matrix.m[2, 2] = 1
Return matrix
End Function

' Fonction pour combiner deux matrices 3x3
Function MultiplyMatrix:TMatrix3x3(m1:TMatrix3x3, m2:TMatrix3x3)
Local result:TMatrix3x3 = New TMatrix3x3
For Local i:Int = 0 To 2
For Local j:Int = 0 To 2
result.m[i, j] = m1.m[i, 0] * m2.m[0, j] + m1.m[i, 1] * m2.m[1, j] + m1.m[i, 2] * m2.m[2, j]
Next
Next
Return result
End Function

' Fonction pour dessiner un objet filaire
Function RenderObject(obj:TObject3D, camera:TCamera)
Local a:Float = ((obj.lineColor Shr 24) & $FF) / 255.0
Local r:Int = (obj.lineColor Shr 16) & $FF
Local g:Int = (obj.lineColor Shr 8) & $FF
Local b:Int = obj.lineColor & $FF
SetAlpha(a)
SetBlend(ALPHABLEND)
SetColor(r, g, b)

For Local i:Int = 0 Until obj.edges.Length / 2
Local p1:TPoint3D = New TPoint3D
p1.x = obj.vertices[obj.edges[i, 0]].x * obj.Scale.x
p1.y = obj.vertices[obj.edges[i, 0]].y * obj.Scale.y
p1.z = obj.vertices[obj.edges[i, 0]].z * obj.Scale.z
p1.r = obj.vertices[obj.edges[i, 0]].r
p1.g = obj.vertices[obj.edges[i, 0]].g
p1.b = obj.vertices[obj.edges[i, 0]].b
p1.a = obj.vertices[obj.edges[i, 0]].a
p1 = TransformPoint(obj.Rotation, p1)
p1 = TranslatePoint(p1, obj.position)
p1 = TransformToCameraSpace(p1, camera)

Local p2:TPoint3D = New TPoint3D
p2.x = obj.vertices[obj.edges[i, 1]].x * obj.Scale.x
p2.y = obj.vertices[obj.edges[i, 1]].y * obj.Scale.y
p2.z = obj.vertices[obj.edges[i, 1]].z * obj.Scale.z
p2.r = obj.vertices[obj.edges[i, 1]].r
p2.g = obj.vertices[obj.edges[i, 1]].g
p2.b = obj.vertices[obj.edges[i, 1]].b
p2.a = obj.vertices[obj.edges[i, 1]].a
p2 = TransformPoint(obj.Rotation, p2)
p2 = TranslatePoint(p2, obj.position)
p2 = TransformToCameraSpace(p2, camera)

Local proj1:TPoint2D = ProjectPoint(p1, camera)
Local proj2:TPoint2D = ProjectPoint(p2, camera)
If proj1 And proj2
DrawLine(proj1.x, proj1.y, proj2.x, proj2.y)
EndIf
Next
End Function

' Normaliser les espaces pour CreateEntityFromOBJ
Function NormalizeWhitespace:String(Input:String)
Local result:String = Input.Replace(Chr(9), " ")
While result.Contains(" ")
result = result.Replace(" ", " ")
Wend
Return result.Trim()
End Function

' Créer un objet à partir d'un fichier .obj
Function CreateEntityFromOBJ:TObject3D(fileName:String)
Local obj:TObject3D = TObject3D.Create()
Local vertices:TList = New TList
Local edges:TList = New TList
Local triangles:TList = New TList
Local edgeSet:TMap = New TMap

Local file:TStream = ReadFile(fileName)
If Not file
Print "Error: Cannot open " + fileName
Return obj
EndIf

While Not Eof(file)
Local line:String = ReadLine(file).Trim()
If line.Length = 0 Or line[0] = Asc("#") Then Continue
line = NormalizeWhitespace(line)
Local parts:String[] = line.Split(" ")
Select parts[0].ToLower()
Case "v"
If parts.Length >= 4
Local vertex:TPoint3D = New TPoint3D
vertex.x = Float(parts[1])
vertex.y = Float(parts[2])
vertex.z = -Float(parts[3])
vertex.r = 255; vertex.g = 255; vertex.b = 255; vertex.a = 255
vertices.AddLast(vertex)
EndIf
Case "f"
If parts.Length >= 4
Local faceIndices:Int[parts.Length - 1]
For Local i:Int = 1 To parts.Length - 1
Local indices:String[] = parts[i].Split("/")
faceIndices[i - 1] = Int(indices[0]) - 1
Next
For Local i:Int = 1 Until faceIndices.Length - 1
triangles.AddLast([faceIndices[0], faceIndices[i], faceIndices[i + 1]])
Next
For Local i:Int = 0 Until faceIndices.Length
Local v1:Int = faceIndices[i]
Local v2:Int = faceIndices[(i + 1) Mod faceIndices.Length]
Local edgeKey:String = Min(v1, v2) + "_" + Max(v1, v2)
If Not edgeSet.Contains(edgeKey)
edgeSet.Insert(edgeKey, edgeKey)
edges.AddLast([v1, v2])
EndIf
Next
EndIf
End Select
Wend
CloseFile(file)

obj.vertices = New TPoint3D[vertices.Count()]
Local i:Int = 0
For Local v:TPoint3D = EachIn vertices
obj.vertices[i] = v
i :+ 1
Next

obj.edges = New Int[edges.Count(), 2]
i = 0
For Local e:Int[] = EachIn edges
obj.edges[i, 0] = e[0]
obj.edges[i, 1] = e[1]
i :+ 1
Next

obj.triangles = New Int[triangles.Count(), 3]
i = 0
For Local t:Int[] = EachIn triangles
obj.triangles[i, 0] = t[0]
obj.triangles[i, 1] = t[1]
obj.triangles[i, 2] = t[2]
i :+ 1
Next

Print "Loaded " + obj.vertices.Length + " vertices, " + obj.edges.Length + " edges, " + obj.triangles.Length + " triangles"
Return obj
End Function

' Fonctions pour manipuler l'objet
Function PositionEntity(obj:TObject3D, x:Float, y:Float, z:Float)
obj.position.x = x
obj.position.y = y
obj.position.z = z
End Function

Function MoveEntity(obj:TObject3D, x:Float, y:Float, z:Float)
obj.position.x :+ x
obj.position.y :+ y
obj.position.z :+ z
End Function

Function TurnEntity(obj:TObject3D, pitch:Float, yaw:Float, roll:Float)
Local pitchMatrix:TMatrix3x3 = RotationMatrixX(pitch * Float(Pi) / 180)
Local yawMatrix:TMatrix3x3 = RotationMatrixY(yaw * Float(Pi) / 180)
Local rollMatrix:TMatrix3x3 = RotationMatrixZ(roll * Float(Pi) / 180)
Local combined:TMatrix3x3 = MultiplyMatrix(MultiplyMatrix(yawMatrix, pitchMatrix), rollMatrix)
obj.Rotation = MultiplyMatrix(combined, obj.Rotation)
obj.UpdateOBB()
End Function

Function RotateEntity(obj:TObject3D, pitch:Float, yaw:Float, roll:Float)
Local pitchMatrix:TMatrix3x3 = RotationMatrixX(pitch * Float(Pi) / 180)
Local yawMatrix:TMatrix3x3 = RotationMatrixY(yaw * Float(Pi) / 180)
Local rollMatrix:TMatrix3x3 = RotationMatrixZ(roll * Float(Pi) / 180)
Local combined:TMatrix3x3 = MultiplyMatrix(MultiplyMatrix(yawMatrix, pitchMatrix), rollMatrix)
obj.Rotation = combined
obj.UpdateOBB()
End Function

Function ScaleEntity(obj:TObject3D, sx:Float, sy:Float, sz:Float)
obj.Scale.x = sx
obj.Scale.y = sy
obj.Scale.z = sz
End Function

' Définir la boîte englobante (OBB) pour un objet
Function EntityBox(entity:Object, minX:Float, minY:Float, minZ:Float, maxX:Float, maxY:Float, maxZ:Float)
If TObject3D(entity)
Local obj:TObject3D = TObject3D(entity)
obj.obbCenter.x = (minX + maxX) / 2
obj.obbCenter.y = (minY + maxY) / 2
obj.obbCenter.z = (minZ + maxZ) / 2
obj.obbExtents.x = (maxX - minX) / 2
obj.obbExtents.y = (maxY - minY) / 2
obj.obbExtents.z = (maxZ - minZ) / 2
obj.obbAxes = obj.Rotation
EndIf
End Function

' Définir l'offset de la sphère de collision
Function EntitySphereOffset(entity:Object, x:Float, y:Float, z:Float)
If TObject3D(entity)
Local obj:TObject3D = TObject3D(entity)
obj.sphereOffset.x = x
obj.sphereOffset.y = y
obj.sphereOffset.z = z
ElseIf TCamera(entity)
Local cam:TCamera = TCamera(entity)
cam.sphereOffset.x = x
cam.sphereOffset.y = y
cam.sphereOffset.z = z
EndIf
End Function

' Fonctions pour manipuler la caméra
Function MoveCamera(camera:TCamera, x:Float, y:Float, z:Float)
Local yaw:Float = ATan2(camera.Rotation.m[0, 2], camera.Rotation.m[2, 2])
Local dx:Float = Cos(yaw) * x - Sin(yaw) * z
Local dz:Float = Sin(yaw) * x + Cos(yaw) * z
camera.position.x :+ dx
camera.position.y :+ y
camera.position.z :+ dz
End Function

Function TurnCamera(camera:TCamera, pitch:Float, yaw:Float, roll:Float)
Local pitchMatrix:TMatrix3x3 = RotationMatrixX(pitch * Float(Pi) / 180)
Local yawMatrix:TMatrix3x3 = RotationMatrixY(yaw * Float(Pi) / 180)
Local rollMatrix:TMatrix3x3 = RotationMatrixZ(roll * Float(Pi) / 180)
Local combined:TMatrix3x3 = MultiplyMatrix(MultiplyMatrix(yawMatrix, pitchMatrix), rollMatrix)
camera.Rotation = MultiplyMatrix(combined, camera.Rotation)
End Function

' Fonctions de collision
Function Collisions(srcType:Int, dstType:Int, collisionMethod:Int, response:Int)
Local rule:TCollision = New TCollision
rule.srcType = srcType
rule.dstType = dstType
rule.collisionMethod = collisionMethod
rule.response = response
collisionRules.AddLast(rule)
End Function

Function EntityType(entity:Object, collisionType:Int)
If TObject3D(entity)
TObject3D(entity).collisionType = collisionType
If Not collisionEntities.Contains(entity)
collisionEntities.AddLast(entity)
EndIf
ElseIf TCamera(entity)
TCamera(entity).collisionType = collisionType
If Not collisionEntities.Contains(entity)
collisionEntities.AddLast(entity)
EndIf
EndIf
End Function

Function EntityRadius(entity:Object, radius:Float)
If TObject3D(entity)
TObject3D(entity).radius = radius
ElseIf TCamera(entity)
TCamera(entity).radius = radius
EndIf
End Function

Function EntityCollided:Object(entity:Object, dstType:Int)
Local srcCenter:TPoint3D = GetSphereCenter(entity)
Local srcRadius:Float
Local srcType:Int

If TObject3D(entity)
srcRadius = TObject3D(entity).radius
srcType = TObject3D(entity).collisionType
ElseIf TCamera(entity)
srcRadius = TCamera(entity).radius
srcType = TCamera(entity).collisionType
Else
Return Null
EndIf

For Local rule:TCollision = EachIn collisionRules
If rule.srcType = srcType And rule.dstType = dstType
For Local dst:Object = EachIn collisionEntities
If dst = entity Then Continue
Local dstObj:TObject3D = TObject3D(dst)
If dstObj And dstObj.collisionType = dstType
Select rule.collisionMethod
Case 1 ' Sphère-sphère
Local dstCenter:TPoint3D = GetSphereCenter(dst)
Local dstRadius:Float = dstObj.radius
Local dx:Float = srcCenter.x - dstCenter.x
Local dy:Float = srcCenter.y - dstCenter.y
Local dz:Float = srcCenter.z - dstCenter.z
Local dist:Float = Sqr(dx * dx + dy * dy + dz * dz)
If dist < srcRadius + dstRadius
Return dst
EndIf
Case 3 ' Sphère-OBB
If SphereOBBCollision(srcCenter, srcRadius, dstObj)
Return dst
EndIf
End Select
EndIf
Next
EndIf
Next
Return Null
End Function

Function UpdateCollisions(camera:TCamera, entity:TObject3D, entity_B:TObject3D)
For Local ent:Object = EachIn collisionEntities
If TObject3D(ent)
TObject3D(ent).lineColor = $FF00FF00
EndIf
Next

For Local src:Object = EachIn collisionEntities
Local srcCenter:TPoint3D = GetSphereCenter(src)
Local srcRadius:Float
Local srcType:Int
Local isOBB:Int = False
Local srcPos:TPoint3D

If TObject3D(src)
Local obj:TObject3D = TObject3D(src)
If obj.position = Null Or obj.obbCenter = Null Or obj.obbExtents = Null
Continue
EndIf
srcPos = obj.position
srcRadius = obj.radius
srcType = obj.collisionType
If src = entity Then isOBB = True
ElseIf TCamera(src)
srcPos = TCamera(src).position
srcRadius = TCamera(src).radius
srcType = TCamera(src).collisionType
Else
Continue
EndIf

If isOBB
Local obj:TObject3D = TObject3D(src)
Local worldCenter:TPoint3D = New TPoint3D
worldCenter.x = obj.position.x + obj.obbCenter.x
worldCenter.y = obj.position.y + obj.obbCenter.y
worldCenter.z = obj.position.z + obj.obbCenter.z
Local lowestY:Float = worldCenter.y - obj.obbExtents.y
If lowestY < 0
srcPos.y = srcPos.y + (0 - lowestY)
If srcType = 3
DrawText("Object on ground (OBB)!", 10, 210)
EndIf
EndIf
Else
If srcCenter.y < srcRadius
srcPos.y = srcPos.y + (srcRadius - srcCenter.y)
If srcType = 1
DrawText("Camera on ground!", 10, 190)
ElseIf srcType = 3
DrawText("Object on ground (Sphere)!", 10, 210)
EndIf
EndIf
EndIf

For Local rule:TCollision = EachIn collisionRules
If rule.srcType = srcType
For Local dst:Object = EachIn collisionEntities
If dst = src Then Continue
Local dstObj:TObject3D = TObject3D(dst)
If dstObj And dstObj.collisionType = rule.dstType
If dstObj = entity And rule.collisionMethod = 3
Local overlap:TPoint3D = New TPoint3D
If SphereOBBCollisionWithResponse(srcCenter, srcRadius, dstObj, overlap)
dstObj.lineColor = $FFFF0000
If TObject3D(src)
TObject3D(src).lineColor = $FFFF0000
EndIf
If rule.response = 1
If TObject3D(src)
srcPos.x = srcPos.x + overlap.x * 0.5
srcPos.y = srcPos.y + overlap.y * 0.5
srcPos.z = srcPos.z + overlap.z * 0.5
ElseIf TCamera(src)
srcPos.x = srcPos.x + overlap.x * 0.5
srcPos.y = srcPos.y + overlap.y * 0.5
srcPos.z = srcPos.z + overlap.z * 0.5
EndIf
dstObj.position.x = dstObj.position.x - overlap.x * 0.5
dstObj.position.y = dstObj.position.y - overlap.y * 0.5
dstObj.position.z = dstObj.position.z - overlap.z * 0.5
EndIf
EndIf
ElseIf dstObj = entity_B And rule.collisionMethod = 1
Local dstCenter:TPoint3D = GetSphereCenter(dst)
Local dstRadius:Float = dstObj.radius
Local dx:Float = srcCenter.x - dstCenter.x
Local dy:Float = srcCenter.y - dstCenter.y
Local dz:Float = srcCenter.z - dstCenter.z
Local dist:Float = Sqr(dx * dx + dy * dy + dz * dz)
If dist < srcRadius + dstRadius
dstObj.lineColor = $FFFF0000
If TObject3D(src)
TObject3D(src).lineColor = $FFFF0000
EndIf
If rule.response = 1
Local overlap:Float = (srcRadius + dstRadius - dist)
Local normalX:Float = dx / dist
Local normalY:Float = dy / dist
Local normalZ:Float = dz / dist
If dist = 0 Then normalX = 0; normalY = 0; normalZ = 1
If TObject3D(src)
srcPos.x = srcPos.x + normalX * overlap * 0.5
srcPos.y = srcPos.y + normalY * overlap * 0.5
srcPos.z = srcPos.z + normalZ * overlap * 0.5
ElseIf TCamera(src)
srcPos.x = srcPos.x + normalX * overlap * 0.5
srcPos.y = srcPos.y + normalY * overlap * 0.5
srcPos.z = srcPos.z + normalZ * overlap * 0.5
EndIf
dstObj.position.x = dstObj.position.x - normalX * overlap * 0.5
dstObj.position.y = dstObj.position.y - normalY * overlap * 0.5
dstObj.position.z = dstObj.position.z - normalZ * overlap * 0.5
EndIf
EndIf
EndIf
EndIf
Next
EndIf
Next
Next
End Function

' Collision sphère-OBB
Function SphereOBBCollision:Int(sphereCenter:TPoint3D, sphereRadius:Float, obj:TObject3D)
Local obbWorldCenter:TPoint3D = New TPoint3D
obbWorldCenter.x = obj.position.x + obj.obbCenter.x
obbWorldCenter.y = obj.position.y + obj.obbCenter.y
obbWorldCenter.z = obj.position.z + obj.obbCenter.z
Local delta:TPoint3D = New TPoint3D
delta.x = sphereCenter.x - obbWorldCenter.x
delta.y = sphereCenter.y - obbWorldCenter.y
delta.z = sphereCenter.z - obbWorldCenter.z
Local invAxes:TMatrix3x3 = New TMatrix3x3
For Local i:Int = 0 To 2
For Local j:Int = 0 To 2
invAxes.m[i, j] = obj.obbAxes.m[j, i]
Next
Next
Local localDelta:TPoint3D = TransformPoint(invAxes, delta)
Local closest:TPoint3D = New TPoint3D
closest.x = Max(-obj.obbExtents.x, Min(localDelta.x, obj.obbExtents.x))
closest.y = Max(-obj.obbExtents.y, Min(localDelta.y, obj.obbExtents.y))
closest.z = Max(-obj.obbExtents.z, Min(localDelta.z, obj.obbExtents.z))
Local dx:Float = localDelta.x - closest.x
Local dy:Float = localDelta.y - closest.y
Local dz:Float = localDelta.z - closest.z
Local distance:Float = Sqr(dx * dx + dy * dy + dz * dz)
Return distance < sphereRadius
End Function

' Collision sphère-OBB avec réponse
Function SphereOBBCollisionWithResponse:Int(sphereCenter:TP oint3D, sphereRadius:Float, obj:TObject3D, overlap:TPoint3D Var)
Local obbWorldCenter:TPoint3D = New TPoint3D
obbWorldCenter.x = obj.position.x + obj.obbCenter.x
obbWorldCenter.y = obj.position.y + obj.obbCenter.y
obbWorldCenter.z = obj.position.z + obj.obbCenter.z
Local delta:TPoint3D = New TPoint3D
delta.x = sphereCenter.x - obbWorldCenter.x
delta.y = sphereCenter.y - obbWorldCenter.y
delta.z = sphereCenter.z - obbWorldCenter.z
Local invAxes:TMatrix3x3 = New TMatrix3x3
For Local i:Int = 0 To 2
For Local j:Int = 0 To 2
invAxes.m[i, j] = obj.obbAxes.m[j, i]
Next
Next
Local localDelta:TPoint3D = TransformPoint(invAxes, delta)
Local closest:TPoint3D = New TPoint3D
closest.x = Max(-obj.obbExtents.x, Min(localDelta.x, obj.obbExtents.x))
closest.y = Max(-obj.obbExtents.y, Min(localDelta.y, obj.obbExtents.y))
closest.z = Max(-obj.obbExtents.z, Min(localDelta.z, obj.obbExtents.z))
Local dx:Float = localDelta.x - closest.x
Local dy:Float = localDelta.y - closest.y
Local dz:Float = localDelta.z - closest.z
Local distance:Float = Sqr(dx * dx + dy * dy + dz * dz)
If distance < sphereRadius And distance > 0
Local penetration:Float = sphereRadius - distance
Local normalLocal:TPoint3D = New TPoint3D
normalLocal.x = dx / distance
normalLocal.y = dy / distance
normalLocal.z = dz / distance
Local normalWorld:TPoint3D = TransformPoint(obj.obbAxes, normalLocal)
overlap.x = normalWorld.x * penetration
overlap.y = normalWorld.y * penetration
overlap.z = normalWorld.z * penetration
Return True
EndIf
overlap.x = 0; overlap.y = 0; overlap.z = 0
Return False
End Function

Function CreateOBBDebugCube:TObject3D(obj:TObject3D)
Local cube:TObject3D = New TObject3D
cube.position = New TPoint3D
cube.position.x = obj.position.x
cube.position.y = obj.position.y
cube.position.z = obj.position.z
cube.Rotation = obj.obbAxes
cube.Scale = New TPoint3D
cube.Scale.x = 1; cube.Scale.y = 1; cube.Scale.z = 1
cube.lineColor = $FFFFFF00
cube.collisionType = 0
cube.vertices = New TPoint3D[8]
Local ex:Float = obj.obbExtents.x
Local ey:Float = obj.obbExtents.y
Local ez:Float = obj.obbExtents.z
Local cx:Float = obj.obbCenter.x
Local cy:Float = obj.obbCenter.y
Local cz:Float = obj.obbCenter.z
cube.vertices[0] = New TPoint3D; cube.vertices[0].x = cx - ex; cube.vertices[0].y = cy - ey; cube.vertices[0].z = cz - ez; cube.vertices[0].r = 255; cube.vertices[0].g = 255; cube.vertices[0].b = 0; cube.vertices[0].a = 255
cube.vertices[1] = New TPoint3D; cube.vertices[1].x = cx + ex; cube.vertices[1].y = cy - ey; cube.vertices[1].z = cz - ez; cube.vertices[1].r = 255; cube.vertices[1].g = 255; cube.vertices[1].b = 0; cube.vertices[1].a = 255
cube.vertices[2] = New TPoint3D; cube.vertices[2].x = cx + ex; cube.vertices[2].y = cy + ey; cube.vertices[2].z = cz - ez; cube.vertices[2].r = 255; cube.vertices[2].g = 255; cube.vertices[2].b = 0; cube.vertices[2].a = 255
cube.vertices[3] = New TPoint3D; cube.vertices[3].x = cx - ex; cube.vertices[3].y = cy + ey; cube.vertices[3].z = cz - ez; cube.vertices[3].r = 255; cube.vertices[3].g = 255; cube.vertices[3].b = 0; cube.vertices[3].a = 255
cube.vertices[4] = New TPoint3D; cube.vertices[4].x = cx - ex; cube.vertices[4].y = cy - ey; cube.vertices[4].z = cz + ez; cube.vertices[4].r = 255; cube.vertices[4].g = 255; cube.vertices[4].b = 0; cube.vertices[4].a = 255
cube.vertices[5] = New TPoint3D; cube.vertices[5].x = cx + ex; cube.vertices[5].y = cy - ey; cube.vertices[5].z = cz + ez; cube.vertices[5].r = 255; cube.vertices[5].g = 255; cube.vertices[5].b = 0; cube.vertices[5].a = 255
cube.vertices[6] = New TPoint3D; cube.vertices[6].x = cx + ex; cube.vertices[6].y = cy + ey; cube.vertices[6].z = cz + ez; cube.vertices[6].r = 255; cube.vertices[6].g = 255; cube.vertices[6].b = 0; cube.vertices[6].a = 255
cube.vertices[7] = New TPoint3D; cube.vertices[7].x = cx - ex; cube.vertices[7].y = cy + ey; cube.vertices[7].z = cz + ez; cube.vertices[7].r = 255; cube.vertices[7].g = 255; cube.vertices[7].b = 0; cube.vertices[7].a = 255
cube.edges = New Int[12, 2]
cube.edges[0, 0] = 0; cube.edges[0, 1] = 1
cube.edges[1, 0] = 1; cube.edges[1, 1] = 2
cube.edges[2, 0] = 2; cube.edges[2, 1] = 3
cube.edges[3, 0] = 3; cube.edges[3, 1] = 0
cube.edges[4, 0] = 4; cube.edges[4, 1] = 5
cube.edges[5, 0] = 5; cube.edges[5, 1] = 6
cube.edges[6, 0] = 6; cube.edges[6, 1] = 7
cube.edges[7, 0] = 7; cube.edges[7, 1] = 4
cube.edges[8, 0] = 0; cube.edges[8, 1] = 4
cube.edges[9, 0] = 1; cube.edges[9, 1] = 5
cube.edges[10, 0] = 2; cube.edges[10, 1] = 6
cube.edges[11, 0] = 3; cube.edges[11, 1] = 7
Return cube
End Function

' Programme principal
Graphics 1920, 1080, 0
SetClsColor 0, 0, 0

' Créer la caméra
Local camera:TCamera = TCamera.Create()
camera.position.y = 100
camera.position.z = -200
camera.focalLength = 500
camera.viewportWidth = 1920
camera.viewportHeight = 1080

' Charger les objets
Local plane:TObject3D = CreateEntityFromOBJ("floor.obj")
PositionEntity(plane, 0, 0, 0)
ScaleEntity(plane, 1, 1, 1)

Local entity:TObject3D = CreateEntityFromOBJ("object.obj")
PositionEntity(entity, 200, 0, 0)
ScaleEntity(entity, 1, 1, 1)

Local entity_B:TObject3D = CreateEntityFromOBJ("tron.obj")
PositionEntity(entity_B, -200, 0, 0)
ScaleEntity(entity_B, 1, 1, 1)

' Configurer les collisions
EntityType(camera, 1)
EntityRadius(camera, 10)
EntitySphereOffset(camera, 0, 0, 0)

EntityType(entity, 3)
'EntityRadius(entity, 100)
EntityBox(entity, -140, 0, -140, 140, 180, 140)

EntityType(entity_B, 3)
EntityRadius(entity_B, 120)
EntitySphereOffset(entity_B, 0, 160, 0)

Collisions(1, 3, 3, 1)
Collisions(1, 3, 1, 1)
Collisions(3, 3, 3, 1)
Collisions(3, 3, 1, 1)

' Variables globales
Local angle:Float = 0
Local useAutoRotation:Int = False
Global Camera_Pitch:Float = 0
Global Camera_Yaw:Float = 0
Global LastMouseX:Int = 1920 / 2
Global LastMouseY:Int = 1080 / 2
Global Camera_VelX:Float = 0
Global Camera_VelZ:Float = 0

' Boucle principale
While Not KeyHit(KEY_ESCAPE)
Cls

' Contrôles de la caméra
If KeyDown(KEY_A) Then MoveCamera(camera, 0, 12, 0)
If KeyDown(KEY_Q) Then MoveCamera(camera, 0, -12, 0)
Proc_Freelook(camera, 1.2, 2.0)

' Contrôles des objets
If KeyDown(KEY_W) Then MoveEntity(entity, -2, 0, 0)
If KeyDown(KEY_X) Then MoveEntity(entity, 2, 0, 0)
If KeyDown(KEY_Z) Then MoveEntity(entity_B, -2, 0, 0)
If KeyDown(KEY_C) Then MoveEntity(entity_B, 2, 0, 0)
If KeyHit(KEY_R) Then RotateEntity(entity, 45, 90, 0)

' Mettre à jour les collisions
UpdateCollisions(camera, entity, entity_B)

' Rendu des objets
RenderObject(entity, camera)
RenderObject(entity_B, camera)
RenderObject(plane, camera)

TurnEntity(entity, 0, 10, 0)

' Rendu du cube de débogage pour l'OBB de entity
Local debugCube:TObject3D = CreateOBBDebugCube(entity)
RenderObject(debugCube, camera)

' Débogage
SetColor 255, 255, 255
DrawText("Camera Pos: X=" + camera.position.x + " Y=" + camera.position.y + " Z=" + camera.position.z, 10, 130)
DrawText("Camera Sphere Offset: X=" + camera.sphereOffset.x + " Y=" + camera.sphereOffset.y + " Z=" + camera.sphereOffset.z, 10, 150)
DrawText("Entity Pos: X=" + entity.position.x + " Y=" + entity.position.y + " Z=" + entity.position.z, 10, 170)
DrawText("Entity_B Pos: X=" + entity_B.position.x + " Y=" + entity_B.position.y + " Z=" + entity_B.position.z, 10, 190)
DrawText("Entity_B Sphere Offset: X=" + entity_B.sphereOffset.x + " Y=" + entity_B.sphereOffset.y + " Z=" + entity_B.sphereOffset.z, 10, 210)

If EntityCollided(camera, 3) = entity Then DrawText("Camera collided with entity (OBB)!", 10, 230)
If EntityCollided(camera, 3) = entity_B Then DrawText("Camera collided with entity_B (sphere)!", 10, 250)
If EntityCollided(entity, 3) Then DrawText("Entity collided with entity_B!", 10, 270)

DrawText("Plane Triangles: " + plane.triangles.Length, 10, 290)
DrawText("Entity OBB Extents: X=" + entity.obbExtents.x + " Y=" + entity.obbExtents.y + " Z=" + entity.obbExtents.z, 10, 310)
DrawText("Entity OBB Center: X=" + (entity.position.x + entity.obbCenter.x) + " Y=" + (entity.position.y + entity.obbCenter.y) + " Z=" + (entity.position.z + entity.obbCenter.z), 10, 330)

Local dx1:Float = camera.position.x - entity.position.x
Local dy1:Float = camera.position.y - entity.position.y
Local dz1:Float = camera.position.z - entity.position.z
Local dist1:Float = Sqr(dx1 * dx1 + dy1 * dy1 + dz1 * dz1)

DrawText("Distance to entity: " + dist1, 10, 350)

Local dx2:Float = camera.position.x - entity_B.position.x
Local dy2:Float = camera.position.y - entity_B.position.y
Local dz2:Float = camera.position.z - entity_B.position.z
Local dist2:Float = Sqr(dx2 * dx2 + dy2 * dy2 + dz2 * dz2)

DrawText("Distance to entity_B: " + dist2, 10, 370)

Flip
Wend

' Fonction Proc_Freelook adaptée pour BlitzMax
Function Proc_Freelook(camera:TCamera, velocity:Float = 1.2, speed:Float = 2.0)
Local MouseX:Int = MouseX()
Local MouseY:Int = MouseY()

Local mouseXDelta:Float = (MouseX - LastMouseX) * 2.5
Local mouseYDelta:Float = (MouseY - LastMouseY) * 2.5

LastMouseX = camera.viewportWidth / 2
LastMouseY = camera.viewportHeight / 2

MoveMouse(LastMouseX, LastMouseY)
Camera_Yaw :- mouseXDelta
Camera_Pitch :+ mouseYDelta

Local pitchMatrix:TMatrix3x3 = RotationMatrixX(Camera_Pitch * Float(Pi) / 180.0)
Local yawMatrix:TMatrix3x3 = RotationMatrixY(Camera_Yaw * Float(Pi) / 180)

camera.Rotation = MultiplyMatrix(pitchMatrix, yawMatrix)

If KeyDown(KEY_LEFT) Or KeyDown(203) Then Camera_VelX :- speed
If KeyDown(KEY_RIGHT) Or KeyDown(205) Then Camera_VelX :+ speed
If KeyDown(KEY_UP) Or KeyDown(200) Then Camera_VelZ :+ speed
If KeyDown(KEY_DOWN) Or KeyDown(208) Then Camera_VelZ :- speed

Camera_VelX :/ velocity
Camera_VelZ :/ velocity

Local yaw:Float = Camera_Yaw * Pi / 180
Local dx:Float = Cos(yaw) * Camera_VelX - Sin(yaw) * Camera_VelZ
Local dz:Float = Sin(yaw) * Camera_VelX + Cos(yaw) * Camera_VelZ

camera.position.x :+ dx
camera.position.z :+ dz

DrawText("mouseX: " + MouseX, 10, 10)
DrawText("mouseY: " + MouseY, 10, 30)
DrawText("mouseXDelta: " + mouseXDelta, 10, 50)
DrawText("mouseYDelta: " + mouseYDelta, 10, 70)
DrawText("Camera_Pitch: " + Camera_Pitch, 10, 90)
DrawText("Camera_Yaw: " + Camera_Yaw, 10, 110)
End Function

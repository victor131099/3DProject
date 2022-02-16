/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/
import Foundation
import UIKit
import SceneKit
import RealityKit
import ARKit
import GTMSessionFetcher
import GoogleSignIn
import SceneKit.ModelIO
import ModelIO
import MetalKit
import GoogleAPIClientForREST
class ViewController: UIViewController, ARSessionDelegate {
    var surfacedata:Data!
    var sceneView = ARSCNView()
    var arraypoint: Array<vector_float3> = []
    private let signInButton = UIButton()
    let service = GTLRDriveService()
    fileprivate var googleAPIs: GoogleDriveAPI?
    @IBOutlet var arView: ARView!
    @IBOutlet weak var hideMeshButton: UIButton!
    @IBOutlet weak var resetButton: UIButton!
    @IBOutlet weak var planeDetectionButton: UIButton!
    var xyzRgbString1 : String = ""
//    @IBOutlet weak var saveButton: RoundedButton!
    let coachingOverlay = ARCoachingOverlayView()
    internal let reconstructButton = UIButton()
    // Cache for 3D text geometries representing the classification values.
    var modelsForClassification: [ARMeshClassification: ModelEntity] = [:]

    /// - Tag: ViewDidLoad
    override func viewDidLoad() {
        super.viewDidLoad()
        GIDSignIn.sharedInstance().delegate = self
                    GIDSignIn.sharedInstance().uiDelegate = self
                    GIDSignIn.sharedInstance().scopes = ["https://www.googleapis.com/auth/drive"]
                    GIDSignIn.sharedInstance()?.signInSilently()
//        arView.session.delegate = self
        
        setupCoachingOverlay()
        addSignInButton()
        arView.environment.sceneUnderstanding.options = []
        
        // Turn on occlusion from the scene reconstruction's mesh.
        arView.environment.sceneUnderstanding.options.insert(.occlusion)
        
        // Turn on physics for the scene reconstruction's mesh.
        arView.environment.sceneUnderstanding.options.insert(.physics)

        // Display a debug visualization of the mesh.
        arView.debugOptions.insert(.showSceneUnderstanding)
        
        // For performance, disable render options that are not required for this app.
        arView.renderOptions = [.disablePersonOcclusion, .disableDepthOfField, .disableMotionBlur]
        
        // Manually configure what kind of AR session to run since
        // ARView on its own does not turn on mesh classification.
        arView.automaticallyConfigureSession = false
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .meshWithClassification

        configuration.environmentTexturing = .automatic
        arView.session.run(configuration)
        addReconstructButton()
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapRecognizer)
       
    }
    internal func createXyzRgbString( pointColors: [UIColor?]) -> String {
                
                var xyzRgbString = ""
                for i in 0..<pointColors.count {
                   
                    let color = pointColors[i]
                  
                    
                    
                    var r: CGFloat = 0
                    var g: CGFloat = 0
                    var b: CGFloat = 0
                    var a: CGFloat = 0
                    if color != nil{
                        color?.getRed(&r, green: &g, blue: &b, alpha: &a)
                    }
                    xyzRgbString.append((r * 255).description)
                    xyzRgbString.append(";")
                    xyzRgbString.append((g * 255).description)
                    xyzRgbString.append(";")
                    xyzRgbString.append((b * 255).description)
                    
                    
                    xyzRgbString += "\n"
                }
                return xyzRgbString
            }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Prevent the screen from being dimmed to avoid interrupting the AR experience.
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    /// Places virtual-text of the classification at the touch-location's real-world intersection with a mesh.
    /// Note - because classification of the tapped-mesh is retrieved asynchronously, we visualize the intersection
    /// point immediately to give instant visual feedback of the tap.
    @objc
    func handleTap(_ sender: UITapGestureRecognizer) {
        // 1. Perform a ray cast against the mesh.
        // Note: Ray-cast option ".estimatedPlane" with alignment ".any" also takes the mesh into account.
        let tapLocation = sender.location(in: arView)
        if let result = arView.raycast(from: tapLocation, allowing: .estimatedPlane, alignment: .any).first {
            // ...
            // 2. Visualize the intersection point of the ray with the real-world surface.
            let resultAnchor = AnchorEntity(world: result.worldTransform)
            resultAnchor.addChild(sphere(radius: 0.01, color: .lightGray))
            arView.scene.addAnchor(resultAnchor, removeAfter: 3)

            // 3. Try to get a classification near the tap location.
            //    Classifications are available addreper face (in the geometric sense, not human faces).
            nearbyFaceWithClassification(to: result.worldTransform.position) { (centerOfFace, classification) in
                // ...
                DispatchQueue.main.async {
                    // 4. Compute a position for the text which is near the result location, but offset 10 cm
                    // towards the camera (along the ray) to minimize unintentional occlusions of the text by the mesh.
                    let rayDirection = normalize(result.worldTransform.position - self.arView.cameraTransform.translation)
                    let textPositionInWorldCoordinates = result.worldTransform.position - (rayDirection * 0.1)
                    
                    // 5. Create a 3D text to visualize the classification result.
                    let textEntity = self.model(for: classification)

                    // 6. Scale the text depending on the distance, such that it always appears with
                    //    the same size on screen.
                    let raycastDistance = distance(result.worldTransform.position, self.arView.cameraTransform.translation)
                    textEntity.scale = .one * raycastDistance

                    // 7. Place the text, facing the camera.
                    var resultWithCameraOrientation = self.arView.cameraTransform
                    resultWithCameraOrientation.translation = textPositionInWorldCoordinates
                    let textAnchor = AnchorEntity(world: resultWithCameraOrientation.matrix)
                    textAnchor.addChild(textEntity)
                    self.arView.scene.addAnchor(textAnchor, removeAfter: 3)

                    // 8. Visualize the center of the face (if any was found) for three seconds.
                    //    It is possible that this is nil, e.g. if there was no face close enough to the tap location.
                    if let centerOfFace = centerOfFace {
                        let faceAnchor = AnchorEntity(world: centerOfFace)
                        faceAnchor.addChild(self.sphere(radius: 0.01, color: classification.color))
                        self.arView.scene.addAnchor(faceAnchor, removeAfter: 3)
                    }
                }
            }
        }
    }
    
    @IBAction func resetButtonPressed(_ sender: Any) {
        if let configuration = arView.session.configuration {
            arView.session.run(configuration, options: .resetSceneReconstruction)
        }
    }
    
    @IBAction func toggleMeshButtonPressed(_ button: UIButton) {
        let isShowingMesh = arView.debugOptions.contains(.showSceneUnderstanding)
        if isShowingMesh {
            arView.debugOptions.remove(.showSceneUnderstanding)
            button.setTitle("Show Mesh", for: [])
        } else {
            arView.debugOptions.insert(.showSceneUnderstanding)
            button.setTitle("Hide Mesh", for: [])
        }
    }
    
    /// - Tag: TogglePlaneDetection
    @IBAction func togglePlaneDetectionButtonPressed(_ button: UIButton) {
        guard let configuration = arView.session.configuration as? ARWorldTrackingConfiguration else {
            return
        }
        if configuration.planeDetection == [] {
            configuration.planeDetection = [.horizontal, .vertical]
            button.setTitle("Stop Plane Detection", for: [])
        } else {
            configuration.planeDetection = []
            button.setTitle("Start Plane Detection", for: [])
        }
        arView.session.run(configuration)
    }
    
    func nearbyFaceWithClassification(to location: SIMD3<Float>, completionBlock: @escaping (SIMD3<Float>?, ARMeshClassification) -> Void) {
        guard let frame = arView.session.currentFrame else {
            completionBlock(nil, .none)
            return
        }
    
        var meshAnchors = frame.anchors.compactMap({ $0 as? ARMeshAnchor })

      // Sort the mesh anchors by distance to the given location and filter out
        // any anchors that are too far away (4 meters is a safe upper limit).
        let cutoffDistance: Float = 4.0
        meshAnchors.removeAll { distance($0.transform.position, location) > cutoffDistance }
        meshAnchors.sort { distance($0.transform.position, location) < distance($1.transform.position, location) }
       // Perform the search asynchronously in order not to stall rendering.
        DispatchQueue.global().async {
            for anchor in meshAnchors {
                for index in 0..<anchor.geometry.faces.count {
                    // Get the center of the face so that we can compare it to the given location.
                    let geometricCenterOfFace = anchor.geometry.centerOf(faceWithIndex: index)
                    
                    // Convert the face's center to world coordinates.
                    var centerLocalTransform = matrix_identity_float4x4
                    centerLocalTransform.columns.3 = SIMD4<Float>(geometricCenterOfFace.0, geometricCenterOfFace.1, geometricCenterOfFace.2, 1)
                    let centerWorldPosition = (anchor.transform * centerLocalTransform).position
                     
                    // We're interested in a classification that is sufficiently close to the given location––within 5 cm.
                    let distanceToFace = distance(centerWorldPosition, location)
                    if distanceToFace <= 0.05 {
                        // Get the semantic classification of the face and finish the search.
                        let classification: ARMeshClassification = anchor.geometry.classificationOf(faceWithIndex: index)
                        completionBlock(centerWorldPosition, classification)
                        return
                    }
                }
            }
            
            // Let the completion block know that no result was found.
            completionBlock(nil, .none)
        }
    }
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        
        
    //            print(pointcolor)
                }
    func exportSurface() {
           
           guard let frame = arView.session.currentFrame else {
               fatalError("Couldn't get the current ARFrame")
           }
           
           // Fetch the default MTLDevice to initialize a MetalKit buffer allocator with
           guard let device = MTLCreateSystemDefaultDevice() else {
               fatalError("Failed to get the system's default Metal device!")
           }
           
           // Using the Model I/O framework to export the scan, so we're initialising an MDLAsset object,
           // which we can export to a file later, with a buffer allocator
           let allocator = MTKMeshBufferAllocator(device: device)
           let asset = MDLAsset(bufferAllocator: allocator)
           
           // Fetch all ARMeshAncors
           let meshAnchors = frame.anchors.compactMap({ $0 as? ARMeshAnchor })
           
           // Convert the geometry of each ARMeshAnchor into a MDLMesh and add it to the MDLAsset
        var xyzRgbString = ""
        var pointcolor : Array<UIColor> = []
           for meshAncor in meshAnchors {
               
               // Some short handles, otherwise stuff will get pretty long in a few lines
               let geometry = meshAncor.geometry
               let vertices = geometry.vertices
               let faces = geometry.faces
               let verticesPointer = vertices.buffer.contents()
               let facesPointer = faces.buffer.contents()
                let normals = geometry.normals
                let normalPointer = normals.buffer.contents()
               // Converting each vertex of the geometry from the local space of their ARMeshAnchor to world space
            arraypoint=[]
            for vertexIndex in 0..<vertices.count {
                   
                   // Extracting the current vertex with an extension method provided by Apple in Extensions.swift
                   let vertex = geometry.vertex(at: UInt32(vertexIndex))
                   
                   // Building a transform matrix with only the vertex position
                   // and apply the mesh anchors transform to convert into world space
                   var vertexLocalTransform = matrix_identity_float4x4
                   vertexLocalTransform.columns.3 = SIMD4<Float>(x: vertex.0, y: vertex.1, z: vertex.2, w: 1)
                   let vertexWorldPosition = (meshAncor.transform * vertexLocalTransform).position
                self.arraypoint.append(vertexWorldPosition)
                   // Writing the world space vertex back into it's position in the vertex buffer
                   let vertexOffset = vertices.offset + vertices.stride * vertexIndex
                   let componentStride = vertices.stride / 3
                   verticesPointer.storeBytes(of: vertexWorldPosition.x, toByteOffset: vertexOffset, as: Float.self)
                   verticesPointer.storeBytes(of: vertexWorldPosition.y, toByteOffset: vertexOffset + componentStride, as: Float.self)
                   verticesPointer.storeBytes(of: vertexWorldPosition.z, toByteOffset: vertexOffset + (2 * componentStride), as: Float.self)
               }
//
            let pixelBuffer = frame.capturedImage
            print("hello")
            let sampler = try? CapturedImageSampler(frame: frame)
//            print(sampler == nil)

        //        print(arraypoint)
        //        print(session.currentFrame?.camera.transform)


            
            
                    for point in arraypoint{


                        
                            let position = SCNVector3(point.x, point.y, point.z);
                            
//                        guard let pointInworld = arView.pointOfView?.convertPosition(position, to: nil) else { return  }
                        let nodePostion = arView.project(point)
                        print(nodePostion)
                        let x = nodePostion!.x/CGFloat(CVPixelBufferGetHeight( pixelBuffer))
                        let y = nodePostion!.y/CGFloat(CVPixelBufferGetWidth( pixelBuffer))
                        print(x)
                        print(y)
                        let color = sampler!.getColor(atX: CGFloat(x), y: CGFloat(y))
                        
                        var r: CGFloat = 0
                        var g: CGFloat = 0
                        var b: CGFloat = 0
                        var a: CGFloat = 0
                        if color != nil{
                            color?.getRed(&r, green: &g, blue: &b, alpha: &a)
                        }
                        xyzRgbString.append((r * 255).description)
                        xyzRgbString.append(";")
                        xyzRgbString.append((g * 255).description)
                        xyzRgbString.append(";")
                        xyzRgbString.append((b * 255).description)
                        
                        
                        xyzRgbString += "\n"
                




                    }
            
            
               // Initializing MDLMeshBuffers with the content of the vertex and face MTLBuffers
               let byteCountVertices = vertices.count * vertices.stride
               let byteCountFaces = faces.count * faces.indexCountPerPrimitive * faces.bytesPerIndex
               let vertexBuffer = allocator.newBuffer(with: Data(bytesNoCopy: verticesPointer, count: byteCountVertices, deallocator: .none), type: .vertex)
               let indexBuffer = allocator.newBuffer(with: Data(bytesNoCopy: facesPointer, count: byteCountFaces, deallocator: .none), type: .index)
               
               // Creating a MDLSubMesh with the index buffer and a generic material
               let indexCount = faces.count * faces.indexCountPerPrimitive
               let material = MDLMaterial(name: "mat1", scatteringFunction: MDLPhysicallyPlausibleScatteringFunction())
               let submesh = MDLSubmesh(indexBuffer: indexBuffer, indexCount: indexCount, indexType: .uInt32, geometryType: .triangles, material: material)
               
               // Creating a MDLVertexDescriptor to describe the memory layout of the mesh
               let vertexFormat = MTKModelIOVertexFormatFromMetal(vertices.format)
               let vertexDescriptor = MDLVertexDescriptor()
               vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: vertexFormat, offset: 0, bufferIndex: 0)
               vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: meshAncor.geometry.vertices.stride)
               
               // Finally creating the MDLMesh and adding it to the MDLAsset
               let mesh = MDLMesh(vertexBuffer: vertexBuffer, vertexCount: meshAncor.geometry.vertices.count, descriptor: vertexDescriptor, submeshes: [submesh])
            mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.5)
               asset.add(mesh)
           }
        self.xyzRgbString1 = xyzRgbString
//        print(xyzRgbString)
//           print("hi")
           // Setting the path to export the OBJ file to
        let fileName = "surface"
        let fileExtension = "obj"
        let fileManager = FileManager.default
                    var tempFileURL = URL(fileURLWithPath: fileName, relativeTo: fileManager.temporaryDirectory)
                    tempFileURL.appendPathExtension(fileExtension)
                    
                    do {
                        // Export mesh to temporary file
                        try
                            asset.export(to: tempFileURL)
                        
                        // Read from file
                        let surfaceFileContents = try Data(contentsOf: tempFileURL)
                        
                        // Discard file
                        try fileManager.removeItem(at: tempFileURL)
                        
                        self.surfacedata = surfaceFileContents
                        
                    } catch {
                        return
                    }
//        print(xyzRgbString)
       }
    func createExportSurfaceFileNameDialog(
                                                  defaultFileName: String){
              
              let fileNameDialog = UIAlertController(
                  title: "File Name",
                  message: "Please provide a name for your exported surface file",
                preferredStyle: .alert
              )
        print("hi")
        print(self.xyzRgbString1)
        print("hellp")
        
              fileNameDialog.addTextField(configurationHandler: {(textField: UITextField!) in
                  textField.text = defaultFileName
                  textField.keyboardType = UIKeyboardType.asciiCapable
              })
            
            exportSurface()
        let color_data: Data! = xyzRgbString1.data(using:.utf8)
        // Add Enter Action
              fileNameDialog.addAction(UIAlertAction(
                  title: "Enter",
                style: UIAlertAction.Style.default,
                  handler: { [weak fileNameDialog] _ in
                      do {
                          let fileName = fileNameDialog?.textFields?[0].text ?? defaultFileName
                            var colorfile = fileName + "color"
                        do{
                            try
                                self.googleAPIs?.upload("1VvYhVKGMK_T6Wi927xWcq7V5khytFgfD", fileName: colorfile, data: color_data, MIMEType: "text/plain", onCompleted: { (fileItem, error) in
                                    guard error == nil, fileItem != nil else {
                                        print(error)
                                        return
                                    }
                                    print("hi")
                                    print(self.surfacedata)
                                    self.googleAPIs?.listFiles("1VvYhVKGMK_T6Wi927xWcq7V5khytFgfD", onCompleted: { (files, error) in
                                        print(error)
                                        print(files)
                                    })
                                })
                            
                                self.googleAPIs?.upload("1VvYhVKGMK_T6Wi927xWcq7V5khytFgfD", fileName: fileName, data: self.surfacedata, MIMEType: "text/plain", onCompleted: { (fileItem, error) in
                                    guard error == nil, fileItem != nil else {
                                        print(error)
                                        return
                                    }
                                    print("hi")
                                    print(self.surfacedata)
                                    self.googleAPIs?.listFiles("1VvYhVKGMK_T6Wi927xWcq7V5khytFgfD", onCompleted: { (files, error) in
                                        print(error)
                                        print(files)
                                    })
                                })
                        }catch{
                            self.showAlert(title: "Export Failure", message: "Please try again")
                        }
                      } catch {
                          self.showAlert(title: "Export Failure", message: "Please try again")
                      }
                  }
              ))
              
              // Add cancel button
            fileNameDialog.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (_) in return }))
            
            self.present(fileNameDialog, animated: true,completion: nil)
          }
    @IBAction func reconstructButtonTapped(sender: UIButton) {
           createExportSurfaceFileNameDialog(defaultFileName: "Surface")
       }
    private func addSignInButton() {
            view.addSubview(signInButton)
            signInButton.translatesAutoresizingMaskIntoConstraints = false
            signInButton.setTitle("Sign In", for: .normal)
            signInButton.setTitleColor(UIColor.red, for: .normal)
            signInButton.backgroundColor = UIColor.white.withAlphaComponent(0.6)
            signInButton.showsTouchWhenHighlighted = true
            signInButton.layer.cornerRadius = 4
            signInButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
            signInButton.addTarget(self, action: #selector(signInButtonTapped(sender:)) , for: .touchUpInside)
            
            // Contraints
            signInButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 50.0).isActive = true
            signInButton.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -8.0).isActive = true
            signInButton.heightAnchor.constraint(equalToConstant: 50)
        }
    @IBAction func signInButtonTapped(sender: UIButton) {
                GIDSignIn.sharedInstance().signIn()
            }
            
    private func addReconstructButton() {
               reconstructButton.isEnabled = true
               view.addSubview(reconstructButton)
               reconstructButton.translatesAutoresizingMaskIntoConstraints = false
               reconstructButton.setTitle("Export Surface", for: .normal)
               reconstructButton.setTitleColor(UIColor.red, for: .normal)
               reconstructButton.setTitleColor(UIColor.gray, for: .disabled)
               reconstructButton.backgroundColor = UIColor.white.withAlphaComponent(0.6)
               reconstructButton.showsTouchWhenHighlighted = true
               reconstructButton.layer.cornerRadius = 4
               reconstructButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
               reconstructButton.addTarget(self, action: #selector(reconstructButtonTapped(sender:)) , for: .touchUpInside)
               
               // Contraints
            reconstructButton .topAnchor.constraint(equalTo: view.topAnchor, constant: 50.0).isActive = true
        reconstructButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 0).isActive = true
               reconstructButton.heightAnchor.constraint(equalToConstant: 50)
           }
    private func showAlert(title: String, message: String) {
                let alert = UIAlertController(
                    title: title,
                    message: message,
                    preferredStyle: UIAlertController.Style.alert
                )
                alert.addAction(UIAlertAction(
                    title: "OK",
                    style: UIAlertAction.Style.default,
                    handler: nil
                ))
            DispatchQueue.main.async{
                self.present(alert, animated: true, completion: nil)
            }
            }
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        DispatchQueue.main.async {
            // Present an alert informing about the error that has occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.resetButtonPressed(self)
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
        
    func model(for classification: ARMeshClassification) -> ModelEntity {
        // Return cached model if available
        if let model = modelsForClassification[classification] {
            model.transform = .identity
            return model.clone(recursive: true)
        }
        
        // Generate 3D text for the classification
        let lineHeight: CGFloat = 0.05
        let font = MeshResource.Font.systemFont(ofSize: lineHeight)
        let textMesh = MeshResource.generateText(classification.description, extrusionDepth: Float(lineHeight * 0.1), font: font)
        let textMaterial = SimpleMaterial(color: classification.color, isMetallic: true)
        let model = ModelEntity(mesh: textMesh, materials: [textMaterial])
        // Move text geometry to the left so that its local origin is in the center
        model.position.x -= model.visualBounds(relativeTo: nil).extents.x / 2
        // Add model to cache
        modelsForClassification[classification] = model
        return model
    }
    
    func sphere(radius: Float, color: UIColor) -> ModelEntity {
        let sphere = ModelEntity(mesh: .generateSphere(radius: radius), materials: [SimpleMaterial(color: color, isMetallic: false)])
        // Move sphere up by half its diameter so that it does not intersect with the mesh
        sphere.position.y = radius
        return sphere
    }
}
extension ViewController: GIDSignInDelegate {
    func sign(_ signIn: GIDSignIn!, didSignInFor user: GIDGoogleUser!, withError error: Error!) {
            if let _ = error {
                
            } else {
                print("Authenticate successfully")
                let service = GTLRDriveService()
                service.authorizer = user.authentication.fetcherAuthorizer()
                self.googleAPIs = GoogleDriveAPI(service: service)
            }
        }
        
        func sign(_ signIn: GIDSignIn!, didDisconnectWith user: GIDGoogleUser!, withError error: Error!) {
            print("Did disconnect to user")
        }
}

extension ViewController: GIDSignInUIDelegate {}

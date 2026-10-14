// SPDX-License-Identifier: Apache-2.0
import Foundation
import Metal

@main
struct MetalProbe {
    static func main() {
        do { try run() }
        catch { fputs("Metal check failed: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func run() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw NSError(domain: "MYT", code: 1, userInfo: [NSLocalizedDescriptionKey:"Metal cihazı bulunamadı."])
        }
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void verify_shared(device const float *input [[buffer(0)]], device float *output [[buffer(1)]], uint index [[thread_position_in_grid]]) {
            float value = input[index];
            for (uint iteration = 0; iteration < 256; ++iteration) value = value * 1.000001f + 0.000001f;
            output[index] = value;
        }
        """
        let options = MTLCompileOptions(); options.fastMathEnabled = false
        let compileStart = ProcessInfo.processInfo.systemUptime
        let library = try device.makeLibrary(source: source, options: options)
        guard let function = library.makeFunction(name: "verify_shared") else { throw NSError(domain:"MYT", code:2) }
        let pipeline = try device.makeComputePipelineState(function: function)
        let compileMS = (ProcessInfo.processInfo.systemUptime - compileStart) * 1000
        let elements = 65536
        let size = elements * MemoryLayout<Float>.stride
        guard let input = device.makeBuffer(length: size, options: .storageModeShared),
              let output = device.makeBuffer(length: size, options: .storageModeShared) else { throw NSError(domain:"MYT",code:3) }
        let inputs = input.contents().bindMemory(to: Float.self, capacity: elements)
        for index in 0..<elements { inputs[index] = Float(index % 100) / 100 }
        var gpuMS: [Double] = [], cpuEncodeMS: [Double] = []
        for sample in 0..<25 {
            let start = ProcessInfo.processInfo.systemUptime
            guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { throw NSError(domain:"MYT",code:4) }
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(input, offset:0,index:0); encoder.setBuffer(output,offset:0,index:1)
            let width = min(pipeline.maxTotalThreadsPerThreadgroup, pipeline.threadExecutionWidth * 4)
            encoder.dispatchThreads(MTLSize(width:elements,height:1,depth:1), threadsPerThreadgroup:MTLSize(width:width,height:1,depth:1))
            encoder.endEncoding(); command.commit()
            let encodedMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
            command.waitUntilCompleted()
            if let error = command.error { throw error }
            if sample >= 5 {
                cpuEncodeMS.append(encodedMS)
                // Missing timestamps are unavailable data, never zero GPU cost.
                if command.gpuStartTime > 0 && command.gpuEndTime >= command.gpuStartTime {
                    gpuMS.append((command.gpuEndTime - command.gpuStartTime) * 1000)
                }
            }
        }
        let values = output.contents().bindMemory(to: Float.self, capacity: elements)
        for index in [0,1,17,100,65535] {
            var expected = inputs[index]
            for _ in 0..<256 { expected = expected * 1.000001 + 0.000001 }
            guard abs(values[index] - expected) < 0.0001 else {
                throw NSError(domain:"MYT",code:5,userInfo:[NSLocalizedDescriptionKey:"GPU sonucu CPU referansıyla eşleşmedi."])
            }
        }
        func mean(_ values: [Double]) -> Any { values.isEmpty ? NSNull() : values.reduce(0,+) / Double(values.count) }
        let result: [String:Any] = [
            "schema":1, "kind":"synthetic_compute_probe", "date":ISO8601DateFormatter().string(from:Date()),
            "device":device.name,"unifiedMemory":device.hasUnifiedMemory,"physicalMemoryBytes":ProcessInfo.processInfo.physicalMemory,
            "storageMode":"shared", "buffersBytes":size * 2,"elements":elements,"iterations":256,
            "pipelineCompileMS":compileMS,"warmSamples":20,"cpuEncodeMeanMS":mean(cpuEncodeMS),"gpuMeanMS":mean(gpuMS),
            "outputValidated":true,"gameFPS":NSNull(),
            "limitations":"Synthetic native Metal compute only; not a game FPS or compatibility result."
        ]
        let data = try JSONSerialization.data(withJSONObject:result, options:[.prettyPrinted,.sortedKeys])
        FileHandle.standardOutput.write(data); print()
    }
}

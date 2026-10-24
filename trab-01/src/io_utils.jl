using Plots
using Random
using Printf

# Coleta informações de hardware e sistema operacional.
function get_hardware_info()
    cpu_model = Sys.CPU_NAME
    if Sys.islinux() && isfile("/proc/cpuinfo")
        for line in readlines("/proc/cpuinfo")
            if startswith(line, "model name")
                parts = split(line, ":")
                if length(parts) > 1
                    cpu_model = strip(parts[2])
                    break
                end
            end
        end
    end
    ram_gb = Sys.total_memory() / (1024^3)
    return (
        os = string(Sys.KERNEL, " ", Sys.ARCH),
        cpu = cpu_model,
        threads = Sys.CPU_THREADS,
        ram = @sprintf("%.2f GB", ram_gb),
        julia_v = string(VERSION)
    )
end

# Retorna o consumo atual de memória RAM do processo em MB.
function get_system_memory_usage()
    if Sys.islinux() && isfile("/proc/self/statm")
        try
            parts = split(read("/proc/self/statm", String))
            pages = parse(Int, parts[2])
            page_size = 4096
            bytes = pages * page_size
            return bytes / (1024^2)
        catch
            return 0.0
        end
    end
    return 0.0
end

# Mede tempo de execução e memória consumida por uma função.
function benchmark_stage(f::Function)
    GC.gc()
    mem_sys_start = get_system_memory_usage()
    
    stats = @timed f()
    
    mem_sys_end = get_system_memory_usage()
    
    return (
        result = stats.value,
        time_sec = stats.time,
        gc_ram_mb = stats.bytes / (1024^2),
        sys_ram_mb = max(0.0, mem_sys_end - mem_sys_start)
    )
end

# Carrega e valida instâncias em formato TXT.
function load_txt_instance(path::String)
    if !isfile(path) || filesize(path) == 0
        error("Arquivo vazio ou inexistente.")
    end
    lines = filter(!isempty, strip.(readlines(path)))
    if isempty(lines)
        error("Arquivo sem conteudo legivel.")
    end
    
    n = tryparse(Int, lines[1])
    if n === nothing || n < 2
        error("Numero de vertices invalido: $(lines[1])")
    end
    if length(lines) < n + 1
        error("Linhas insuficientes: esperado $(n + 1), lido $(length(lines))")
    end
    
    C = zeros(Float64, n, n)
    for i in 1:n
        tokens = split(lines[i + 1])
        if length(tokens) != n
            error("Linha $i tem $(length(tokens)) colunas (esperado $n)")
        end
        for j in 1:n
            val = tryparse(Float64, tokens[j])
            if val === nothing
                error("Caractere invalido em ($i, $j): $(tokens[j])")
            end
            if val < 0.0
                error("Custo negativo em ($i, $j): $val")
            end
            C[i, j] = val
        end
    end
    return n, C
end

# Carrega e valida instâncias em formato ATSP da TSPLIB.
function load_atsp_instance(path::String)
    if !isfile(path) || filesize(path) == 0
        error("Arquivo vazio ou inexistente.")
    end
    lines = readlines(path)
    n = 0
    raw_values = Float64[]
    in_weight_section = false
    
    for line in lines
        clean_line = strip(line)
        if isempty(clean_line)
            continue
        end
        if startswith(uppercase(clean_line), "DIMENSION")
            parts = split(clean_line, ":")
            n = parse(Int, strip(parts[end]))
        elseif startswith(uppercase(clean_line), "EDGE_WEIGHT_SECTION")
            in_weight_section = true
            continue
        elseif startswith(uppercase(clean_line), "EOF") || startswith(uppercase(clean_line), "TOUR_SECTION")
            break
        end
        
        if in_weight_section
            line_data = split(clean_line)
            for val in line_data
                push!(raw_values, parse(Float64, val))
            end
        end
    end
    
    if n == 0 || length(raw_values) < n * n
        error("Formato atsp invalido ou pesos insuficientes.")
    end
    
    C = zeros(Float64, n, n)
    idx = 1
    for i in 1:n, j in 1:n
        C[i, j] = raw_values[idx]
        idx += 1
    end
    return n, C
end

# Gera a representação gráfica do caminho percorrido e salva em arquivo PNG.
function generate_path_plot(n::Int, arcs::Vector{Tuple{Int, Int}}, instance_name::String, output_folder::String)
    if isempty(arcs) return end
    if !isdir(output_folder) mkpath(output_folder) end
    gr()
    
    seed = hash(instance_name) % 10000
    Random.seed!(abs(seed))
    x_nodes = rand(5.0:95.0, n)
    y_nodes = rand(5.0:95.0, n)
    
    p = plot(
        title = "PCHM MTZ - $instance_name (n = $n)",
        titlefont = font(11, :bold),
        size = (1000, 800),
        grid = true,
        gridalpha = 0.15,
        background_color = :white,
        legend = :topright
    )
    
    adj = Dict(u => v for (u, v) in arcs)
    sequence = Int[]
    current = 1
    push!(sequence, current)
    while haskey(adj, current) && length(sequence) < n
        current = adj[current]
        push!(sequence, current)
    end
    
    gradient = cgrad(:viridis, max(1, length(sequence) - 1), categorical=true)
    if length(sequence) > 1
        for idx in 1:(length(sequence) - 1)
            u = sequence[idx]
            v = sequence[idx + 1]
            plot!([x_nodes[u], x_nodes[v]], [y_nodes[u], y_nodes[v]], color = gradient[idx], linewidth = 2.0, alpha = 0.85, label = "")
            
            mx = (x_nodes[u] + x_nodes[v]) / 2.0
            my = (y_nodes[u] + y_nodes[v]) / 2.0
            scatter!([mx], [my], marker = :utriangle, markersize = 4, color = gradient[idx], markerstrokewidth = 0, label = "")
        end
    end
    
    scatter!(x_nodes, y_nodes, markersize = (n > 50 ? 5 : 7), color = :lightgrey, markerstrokecolor = :black, markerstrokewidth = 0.5, label = "Vertices")
    scatter!([x_nodes[1]], [y_nodes[1]], color = :lime, markersize = 12, marker = :square, label = "Origem (s=1)")
    scatter!([x_nodes[n]], [y_nodes[n]], color = :crimson, markersize = 12, marker = :star8, label = "Destino (t=$n)")
    
    if n <= 60
        for i in 1:n annotate!(x_nodes[i], y_nodes[i] + 2.0, text(string(i), :black, :center, :bold, 6)) end
    end
    
    output_png = replace(instance_name, r"\.(txt|atsp)$" => ".png")
    savefig(p, joinpath(output_folder, output_png))
end

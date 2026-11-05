ENV["GKSwstype"] = "100"

using Plots
using Random
using Printf

include("grasp_solver.jl")
include("instancia_utils.jl")

# Executa a calibração conjunta (grid search) de alpha x iterações em todas as instâncias.
function execute_grid_calibration()
    target_dir = "instancias-professor"
    atsp_files = sort(filter(f -> endswith(f, ".atsp"), readdir(target_dir)))
    if !ispath("data") mkpath("data") end

    alpha_scale = [0.0, 0.05, 0.15, 0.30, 0.50, 1.0]
    iter_scale = [100, 250, 500, 750, 1000]
    num_instances = length(atsp_files)

    gap = Dict((a, k) => 0.0 for a in alpha_scale, k in iter_scale)
    imp = Dict((a, k) => 0.0 for a in alpha_scale, k in iter_scale)
    tempo = Dict((a, k) => 0.0 for a in alpha_scale, k in iter_scale)
    otimos = Dict((a, k) => 0 for a in alpha_scale, k in iter_scale)

    open(joinpath("data", "calibracao_grid.csv"), "w") do f
        write(f, "Instancia;N;Alpha;Iteracoes;Z_PLI;Z_Inicial;Z_GRASP;Tempo_s;Gap_PLI_Percentual;Melhoria_Percentual\n")
        for file in atsp_files
            n, costs = load_atsp_instance(joinpath(target_dir, file))
            z_init = calculate_route_cost(run_initial_heuristic(n, costs), costs)
            z_pli = Z_PLI_TP1[file]
            for a in alpha_scale
                Random.seed!(42)
                _, _, history = run_grasp_metaheuristic(n, costs, maximum(iter_scale), a; checkpoints=iter_scale)
                for k in iter_scale
                    zk, tk, _ = history[k]
                    g = (zk - z_pli) / z_pli * 100.0
                    m = (z_init - zk) / z_init * 100.0
                    gap[(a, k)] += g / num_instances
                    imp[(a, k)] += m / num_instances
                    tempo[(a, k)] += tk
                    otimos[(a, k)] += (zk <= z_pli) ? 1 : 0
                    write(f, "$file;$n;$a;$k;$z_pli;$z_init;$zk;$(round(tk, digits=4));$(round(g, digits=2));$(round(m, digits=2))\n")
                end
                println(@sprintf("%-12s alpha=%.2f concluido (Z_1000 = %.0f)", file, a, history[1000][1]))
            end
        end
    end

    # Critério de escolha: menor Gap médio; empate (diferença < 0,01 p.p.) decidido pelo menor tempo.
    combos = [(a, k) for a in alpha_scale for k in iter_scale]
    best = combos[1]
    for c in combos
        if gap[c] < gap[best] - 1e-2 || (abs(gap[c] - gap[best]) <= 1e-2 && tempo[c] < tempo[best])
            best = c
        end
    end

    open(joinpath("data", "calibracao_resumo.csv"), "w") do f
        write(f, "Alpha;Iteracoes;Gap_PLI_Medio_Percentual;Melhoria_Media_Percentual;Tempo_Total_s;Instancias_no_Otimo\n")
        for c in combos
            write(f, "$(c[1]);$(c[2]);$(round(gap[c], digits=2));$(round(imp[c], digits=2));$(round(tempo[c], digits=2));$(otimos[c])\n")
        end
    end
    open(joinpath("data", "parametros_escolhidos.txt"), "w") do f
        write(f, "alpha=$(best[1])\niteracoes=$(best[2])\n")
    end

    generate_grid_plots(alpha_scale, iter_scale, gap, tempo, best, "data/plots")

    println(repeat("-", 90))
    println(@sprintf("%-6s | %5s | %10s | %10s | %10s | %6s", "Alpha", "Iter", "Gap Medio", "Melhoria", "Tempo", "Otimos"))
    for c in combos
        println(@sprintf("%-6.2f | %5d | %9.2f%% | %9.2f%% | %9.2fs | %6d", c[1], c[2], gap[c], imp[c], tempo[c], otimos[c]))
    end
    println(@sprintf("MELHOR COMBINACAO: alpha = %.2f | iteracoes = %d | Gap medio = %.2f%% | Tempo total = %.2fs",
                     best[1], best[2], gap[best], tempo[best]))
end

# Gera o mapa de calor do Gap médio e as curvas de Gap/Tempo por iteração para cada alpha.
function generate_grid_plots(alpha_scale, iter_scale, gap, tempo, best, output_folder)
    if !isdir(output_folder) mkpath(output_folder) end
    gr()

    a_labels = [@sprintf("%.2f", a) for a in alpha_scale]
    M = [gap[(a, k)] for a in alpha_scale, k in iter_scale]
    hm = heatmap(
        1:length(iter_scale), 1:length(alpha_scale), M,
        xticks = (1:length(iter_scale), string.(iter_scale)),
        yticks = (1:length(alpha_scale), a_labels),
        xlabel = "Numero de Iteracoes", ylabel = "Fator Alpha",
        title = "Gap Medio em Relacao ao PLI (%) por Combinacao",
        titlefont = font(10), color = cgrad(:RdYlGn, rev = true),
        colorbar_title = "Gap (%)", size = (800, 520), margin = 6Plots.mm
    )
    for (i, a) in enumerate(alpha_scale), (j, k) in enumerate(iter_scale)
        txt = @sprintf("%.2f%%", gap[(a, k)])
        annotate!(hm, j, i, text((a, k) == best ? "[" * txt * "]" : txt, :black, :center, 8))
    end
    savefig(hm, joinpath(output_folder, "calibracao_heatmap.png"))

    palette_c = [:black, :orange, :crimson, :royalblue, :green, :purple]
    p1 = plot(title = "Gap Medio PLI vs. Iteracoes (por Alpha)", titlefont = font(10),
              xlabel = "Numero de Iteracoes", ylabel = "Gap Medio em Relacao ao PLI (%)",
              xticks = iter_scale, legend = :topright, grid = true, gridalpha = 0.25)
    p2 = plot(title = "Tempo Total vs. Iteracoes (por Alpha)", titlefont = font(10),
              xlabel = "Numero de Iteracoes", ylabel = "Tempo Total nas 13 Instancias (s)",
              xticks = iter_scale, legend = :topleft, grid = true, gridalpha = 0.25)
    for (i, a) in enumerate(alpha_scale)
        lw = a == best[1] ? 3.5 : 1.8
        plot!(p1, iter_scale, [gap[(a, k)] for k in iter_scale], label = "alpha = $(a_labels[i])",
              marker = :circle, markersize = 4, linewidth = lw, color = palette_c[i])
        plot!(p2, iter_scale, [tempo[(a, k)] for k in iter_scale], label = "alpha = $(a_labels[i])",
              marker = :circle, markersize = 4, linewidth = lw, color = palette_c[i])
    end
    p = plot(p1, p2, layout = (1, 2), size = (1150, 450), margin = 6Plots.mm, background_color = :white)
    savefig(p, joinpath(output_folder, "calibracao_curvas.png"))
end

if abspath(PROGRAM_FILE) == @__FILE__
    execute_grid_calibration()
end
